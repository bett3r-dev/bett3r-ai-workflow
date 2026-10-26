#!/usr/bin/env python3
"""Capture this Claude conversation into Blueprint's memory (ML-1 F28, F17).

Two entry points, one send:

  blueprint-capture.py hook   the Stop and SessionEnd hooks (hooks/blueprint-capture.sh)
  blueprint-capture.py send   bin/blueprint-send, which /blueprint-send and the ask run

The repository opts in from its checked-in settings (`env.BLUEPRINT_CAPTURE_REPOSITORY`,
its name in Blueprint); each person sets BLUEPRINT_CAPTURE to off, ask (the default) or
always. In `ask`, the first Stop of a session blocks once with an instruction for the
agent to ask the person; a yes runs `blueprint-send --consent`, which records it, and
SessionEnd then sends the whole conversation (Blueprint replaces a conversation sent
again). In `always`, SessionEnd sends unasked. A choice is by message: --redact or
--anyway covers the messages the person was shown when they chose (those of the last
warning, else of the send) that no earlier choice covers, and an earlier choice is never
re-decided. Every send keeps each message's choice (a match there redacted, or sent as it
is); a match not wholly inside chosen messages blocks with the warning, as with no choice.
After --text (an edit) SessionEnd sends nothing again. A run nobody watches (`claude -p` and the
SDKs, a lane, a Steward design run) is never asked: the ask would replace its answer.
A secret SessionEnd finds is left as a pending record of the repository, which the next
SessionStart in it raises so the person can redact, edit or send anyway.

A send renders the transcript (prompts and replies in full, tool calls and tool output
cut to 400 characters, a private key that starts before the cut kept through its END
marker or, with no END marker of its own, cut at its header; no thinking, meta or
system lines), runs Blueprint's secret check (POST /secret-check) and stops on a match
with "This looks like a secret"; otherwise it takes an upload grant (POST
/documents/upload-grant), posts the bytes to the bucket with the grant's fields and
their SHA-256 checksum (D44), and names the object to CaptureConversation (D59). Every failure is one line; a hook always exits 0.

Host: BLUEPRINT_HOST_URL, else the /blueprint connect record in the git dir (whose
sessionId the capture is attached to). Token: BLUEPRINT_ACCESS_TOKEN, else the
blueprint CLI's credentials file (~/.config/blueprint/credentials.json).
"""

import base64
import hashlib
import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

CUT = 400
# Only where a cut may fall, never a secret check: that is Blueprint's (POST /secret-check).
PEM_HEADER = re.compile(r"(?i)-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----")
PEM_END = re.compile(r"(?i)-----END[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----")
QUESTION = "Send this conversation to Blueprint's memory?"
SECRET = "This looks like a secret"
TIMEOUT = 5
# /secret-check reads at most 1 MiB of JSON; each request carries less. The text goes in
# blocks of BLOCK characters, and each piece repeats the last OVERLAP blocks of the one
# before, so a secret shorter than OVERLAP * BLOCK characters across the cut is found.
CHECK_BYTES = 900_000
BLOCK = 8_192
OVERLAP = 2
# The entry points `claude -p` and the Agent SDKs run under (CLAUDE_CODE_ENTRYPOINT).
UNWATCHED = ("sdk-cli", "sdk-ts", "sdk-py", "claude-code-github-action")

SENT, FAILED, USAGE, BLOCKED = 0, 1, 2, 3


class Unreachable(Exception):
    pass


# ---- where things are -------------------------------------------------------

def mode_of(env):
    """off, ask or always; anything else is the default, ask, which sends nothing unasked."""
    value = (env.get("BLUEPRINT_CAPTURE") or "").strip().lower()
    return value if value in ("off", "ask", "always") else "ask"


def git_dir(env, project):
    gd = env.get("GIT_DIR") or ".git"
    if not os.path.isabs(gd):
        gd = os.path.join(project, gd)
    if os.path.isfile(gd):
        try:
            with open(gd, encoding="utf-8") as f:
                line = f.readline().strip()
        except OSError:
            return gd
        if line.startswith("gitdir: "):
            gd = line[len("gitdir: "):]
            if not os.path.isabs(gd):
                gd = os.path.join(project, gd)
    return gd


def target(env, project):
    """(host, the Blueprint session the checkout is connected to or "")."""
    host = (env.get("BLUEPRINT_HOST_URL") or "").strip()
    if host:
        return host.rstrip("/"), ""
    try:
        with open(os.path.join(git_dir(env, project), "blueprint-connection.json"), encoding="utf-8") as f:
            record = json.load(f)
    except (OSError, ValueError):
        return "", ""
    if not isinstance(record, dict) or not isinstance(record.get("host"), str):
        return "", ""
    about = record.get("sessionId")
    return record["host"].strip().rstrip("/"), about if isinstance(about, str) else ""


def home(env):
    return env.get("HOME") or os.path.expanduser("~")


def token_of(env, host):
    if env.get("BLUEPRINT_ACCESS_TOKEN"):
        return env["BLUEPRINT_ACCESS_TOKEN"]
    parts = urllib.parse.urlsplit(host)
    origin = "%s://%s" % (parts.scheme, parts.netloc)
    try:
        with open(os.path.join(home(env), ".config", "blueprint", "credentials.json"), encoding="utf-8") as f:
            secret = json.load(f)["accounts"][origin]
        token = json.loads(secret)["token"]
    except (OSError, ValueError, KeyError, TypeError):
        return ""
    return token if isinstance(token, str) else ""


def state_dir(env):
    base = env.get("XDG_STATE_HOME") or os.path.join(home(env), ".local", "state")
    return os.path.join(base, "blueprint", "capture")


def slug(name):
    return re.sub(r"[^A-Za-z0-9._-]", "_", name)


def marker(env, session_id, kind="asked"):
    """asked-<id>: the session was asked (or told why not); yes-<id>: its person said yes,
    holding "text" on its first line after an edit, and after it one "<choice> <message>"
    line for each message a --redact or --anyway covers; shown-<id>: the messages of the
    last warning about it."""
    return os.path.join(state_dir(env), kind + "-" + slug(session_id))


def mark(env, session_id, kind="asked", content=""):
    try:
        os.makedirs(state_dir(env), mode=0o700, exist_ok=True)
        with open(marker(env, session_id, kind), "w", encoding="utf-8") as f:
            f.write(content)
    except OSError:
        pass


def read_marker(env, session_id, kind):
    """The marker's lines, or None without it."""
    try:
        with open(marker(env, session_id, kind), encoding="utf-8") as f:
            return f.read().split("\n")
    except OSError:
        return None


def edited(env, session_id):
    """None without a yes; True when the yes is an edit's, which is final."""
    lines = read_marker(env, session_id, "yes")
    return None if lines is None else lines[0].strip() == "text"


def choices_of(env, session_id):
    """{message: "redact" or "anyway"}: each message's choice, as the yes keeps it."""
    out = {}
    for line in (read_marker(env, session_id, "yes") or [])[1:]:
        choice, _, message = line.partition(" ")
        if choice in ("redact", "anyway") and message:
            out[message] = choice
    return out


def shown_of(env, session_id):
    """The messages (sha256 of their transcript lines) the last warning showed, or None."""
    lines = read_marker(env, session_id, "shown")
    return None if lines is None else {line for line in lines if line}


def pending_dir(env, repository):
    """The secrets found at a SessionEnd of this repository, one JSON file a conversation."""
    return os.path.join(state_dir(env), "pending", slug(repository))


def unwatched(env, project, cwd):
    """True in a run nobody answers: `claude -p` or an SDK, a lane, a Steward design run."""
    if (env.get("CLAUDE_CODE_ENTRYPOINT") or "") in UNWATCHED:
        return True
    for d in (project, cwd):
        if d and (os.path.isfile(os.path.join(d, ".work", "lane.yaml")) or re.search(r"\.blueprint-worktrees/.", d)):
            return True
    return False


def find_transcript(env, project, session_id):
    """This project's transcript for session_id, else its newest one, else ""."""
    config = env.get("CLAUDE_CONFIG_DIR") or os.path.join(home(env), ".claude")
    folder = os.path.join(config, "projects", re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(project)))
    if session_id:
        path = os.path.join(folder, session_id + ".jsonl")
        return path if os.path.isfile(path) else ""
    try:
        names = [n for n in os.listdir(folder) if n.endswith(".jsonl")]
    except OSError:
        return ""
    if not names:
        return ""
    return max((os.path.join(folder, n) for n in names), key=os.path.getmtime)


# ---- what is sent -----------------------------------------------------------

def cut(text):
    """The first CUT characters, extended so a private key whose header starts before
    the cut is kept through its END marker and the secret check sees it whole. A
    header before the cut with no END marker of its own (none after it, or another
    header before the next one) moves the cut back to its start, so nothing of that
    key, nor anything after it, is kept."""
    end = CUT
    for m in PEM_HEADER.finditer(text):
        if m.start() >= end:
            break
        close = PEM_END.search(text, m.end())
        later = PEM_HEADER.search(text, m.end())
        if not close or (later and later.start() < close.start()):
            end = m.start()
            break
        end = max(end, close.end())
    return text if len(text) <= end else text[:end] + " [cut: %d more characters]" % (len(text) - end)


def result_text(content):
    if isinstance(content, str):
        return content
    out = []
    for block in content if isinstance(content, list) else []:
        if isinstance(block, dict) and block.get("type") == "text":
            out.append(str(block.get("text", "")))
        elif isinstance(block, dict):
            out.append("[%s]" % block.get("type", "?"))
    return "\n".join(out)


def parts_of(raw):
    """One transcript line as text: prompts and replies in full, tool calls and output cut."""
    try:
        entry = json.loads(raw)
    except ValueError:
        return []
    if not isinstance(entry, dict) or entry.get("isMeta") or entry.get("isSidechain"):
        return []
    kind = entry.get("type")
    if kind not in ("user", "assistant"):
        return []
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return ["%s: %s" % (kind, content)]
    parts = []
    for block in content if isinstance(content, list) else []:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            parts.append("%s: %s" % (kind, block.get("text", "")))
        elif block.get("type") == "tool_use":
            parts.append("tool call %s: %s" % (block.get("name", "?"), cut(json.dumps(block.get("input", {}), ensure_ascii=False))))
        elif block.get("type") == "tool_result":
            parts.append("tool output: %s" % cut(result_text(block.get("content", ""))))
    return parts


def messages(path):
    """[(id, parts)] of the transcript, in order; a message's id is the sha256 of its line."""
    with open(path, encoding="utf-8", errors="replace") as f:
        return [(hashlib.sha256(raw.encode("utf-8")).hexdigest(), parts_of(raw)) for raw in f]


def render(msgs, choices=None):
    """(text, pieces): the conversation as text, and [start, end, choice] covering all of
    it, choice being the message's in choices (None for one without), the "\n\n" between
    two parts the more careful of theirs (redact over anyway, None over both)."""
    parts, pieces, at = [], [], 0
    choices = choices or {}
    for message, texts in msgs:
        for text in texts:
            choice = choices.get(message)
            if parts:
                before = pieces[-1][2]
                pieces.append([at, at + 2, None if None in (before, choice) else
                               "redact" if "redact" in (before, choice) else "anyway"])
                at += 2
            pieces.append([at, at + len(text), choice])
            parts.append(text)
            at += len(text)
    pieces.append([at, at + 1, None])
    return "\n\n".join(parts) + "\n", pieces


def chosen(span, pieces):
    """A span's choice: None unless every character of it lies in chosen text; "redact" if
    any of it lies in text chosen to be redacted; else "anyway"."""
    start, end = span[0], max(span[1], span[0] + 1)
    seen = {p[2] for p in pieces if p[0] < end and start < p[1] and p[0] < p[1]}
    if not seen or None in seen:
        return None
    return "redact" if "redact" in seen else "anyway"


# ---- Blueprint --------------------------------------------------------------

def request(url, body, headers):
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            return res.status, res.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Unreachable(str(getattr(e, "reason", e)))


def post_json(host, token, path, obj):
    status, raw = request(host + path, json.dumps(obj).encode(), {
        "Content-Type": "application/json", "Accept": "application/json", "Authorization": "Bearer " + token})
    try:
        answer = json.loads(raw or b"{}")
    except ValueError:
        answer = {}
    return status, answer if isinstance(answer, dict) else {}


def chunks(text):
    """(offset, piece) pairs whose JSON stays under CHECK_BYTES: blocks of BLOCK characters
    (at most 12 JSON bytes each), each piece after the first starting OVERLAP blocks
    before the end of the one before."""
    sizes = [len(json.dumps(text[k:k + BLOCK])) - 2 for k in range(0, len(text), BLOCK)]
    out, first = [], 0
    while True:
        last, size = first, 0
        while last < len(sizes) and (last == first or size + sizes[last] <= CHECK_BYTES):
            size += sizes[last]
            last += 1
        out.append((first * BLOCK, text[first * BLOCK:last * BLOCK]))
        if last >= len(sizes):
            return out
        first = max(first + 1, last - OVERLAP)


def from_utf16(piece, units):
    """The index in piece of each UTF-16 offset in units (the route counts as JavaScript does)."""
    want, at, u = sorted(set(units)), {}, 0
    k = 0
    for index, ch in enumerate(piece):
        while k < len(want) and want[k] <= u:
            at[want[k]] = index
            k += 1
        u += 2 if ord(ch) > 0xFFFF else 1
    for w in want[k:]:
        at[w] = len(piece)
    return at


def secret_spans(host, token, text):
    """[(start, end, rule)] in text, or a string saying why the check could not run."""
    spans = []
    for offset, piece in chunks(text):
        status, answer = post_json(host, token, "/secret-check", {"text": piece})
        if status != 200 or not isinstance(answer.get("spans"), list):
            return "the secret check answered %d; nothing was sent" % status
        found = [s for s in answer["spans"] if isinstance(s, dict)]
        at = from_utf16(piece, [s.get("start", 0) for s in found] + [s.get("end", 0) for s in found])
        spans += [(offset + at[s.get("start", 0)], offset + at[s.get("end", 0)], str(s.get("rule", "secret"))) for s in found]
    return sorted(set(spans))  # a match in the overlap of two pieces comes back from both


def redact(text, spans):
    """Each span replaced by a marker; a span that starts inside the one before extends
    that marker to its own end."""
    out, last = [], 0
    for start, end, rule in spans:
        if start < last:
            last = max(last, end)
            continue
        out.append(text[last:start])
        out.append("[redacted: %s]" % rule)
        last = end
    out.append(text[last:])
    return "".join(out)


def multipart(fields, data):
    boundary = uuid.uuid4().hex
    out = []
    for k, v in fields:
        out.append(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (boundary, k, v)).encode())
    out.append(('--%s\r\nContent-Disposition: form-data; name="file"; filename="conversation.txt"\r\n'
                'Content-Type: text/plain\r\n\r\n' % boundary).encode())
    out.append(data)
    out.append(("\r\n--%s--\r\n" % boundary).encode())
    return b"".join(out), "multipart/form-data; boundary=" + boundary


def upload_and_capture(host, token, repository, conversation, about, data):
    """(code, line): the grant, the bytes to the bucket, then CaptureConversation."""
    digest = hashlib.sha256(data).digest()
    sha = digest.hex()
    status, grant = post_json(host, token, "/documents/upload-grant", {"sha": sha, "size": len(data), "type": "text/plain"})
    if status != 200 or not isinstance(grant.get("fields"), dict) or not grant.get("url"):
        why = grant.get("error") or "answered %d" % status
        return FAILED, "the upload was not granted (%s); nothing was sent" % why
    fields = [(str(k), str(v)) for k, v in grant["fields"].items()]
    names = {k for k, _ in fields}
    if "Content-Type" not in names:
        fields.append(("Content-Type", "text/plain"))
    if "x-amz-checksum-sha256" not in names:
        fields += [("x-amz-checksum-algorithm", "SHA256"), ("x-amz-checksum-sha256", base64.b64encode(digest).decode())]
    body, kind = multipart(fields, data)
    status, _ = request(grant["url"], body, {"Content-Type": kind})
    if not 200 <= status < 300:
        return FAILED, "the store refused the upload (%d); nothing was captured" % status
    capture = {"repository": repository, "conversation": conversation, "url": grant.get("object_url", ""), "sha": sha, "size": len(data)}
    if about:
        capture["session"] = about
    status, answer = post_json(host, token, "/api/conversations/capture-conversation", capture)
    if not 200 <= status < 300:
        return FAILED, "CaptureConversation was refused (%s); the conversation is not in the memory" % (
            answer.get("message") or answer.get("error") or status)
    return SENT, "sent this conversation (%s, %d bytes) to Blueprint's memory of %s." % (conversation, len(data), repository)


def send(env, project, transcript, session_id, text_file="", choice=""):
    """(code, lines) for one send. choice is "", "redact" or "anyway", and covers the
    messages of the last warning (else every one) that no earlier choice covers; a match
    wholly inside chosen messages is redacted or sent as it is, any other blocks."""
    repository = (env.get("BLUEPRINT_CAPTURE_REPOSITORY") or "").strip()
    if not repository:
        return FAILED, ["this repository does not capture conversations: its settings name no BLUEPRINT_CAPTURE_REPOSITORY; nothing was sent"]
    if not transcript:
        transcript = find_transcript(env, project, session_id)
    if not transcript or not os.path.isfile(transcript):
        return FAILED, ["no transcript of this conversation was found; nothing was sent"]
    conversation = session_id or os.path.splitext(os.path.basename(transcript))[0]
    host, about = target(env, project)
    if not host:
        return FAILED, ["no Blueprint host: run /blueprint connect or set BLUEPRINT_HOST_URL; nothing was sent"]
    token = token_of(env, host)
    if not token:
        return FAILED, [no_token(host) + "; nothing was sent"]
    try:
        msgs, pieces, choices = [], [], {}
        if text_file:  # an edit is new text: it covers nothing
            with open(text_file, encoding="utf-8") as f:
                text = f.read()
        else:
            msgs = messages(transcript)
            choices = choices_of(env, conversation)
            if choice:
                shown = shown_of(env, conversation)
                for message, _ in msgs:
                    if (shown is None or message in shown) and message not in choices:
                        choices[message] = choice
            text, pieces = render(msgs, choices)
        spans = secret_spans(host, token, text)
        if isinstance(spans, str):
            return FAILED, [spans]
        new = [s for s in spans if chosen(s, pieces) is None]
        if new:
            return BLOCKED, blocked(env, text, new, transcript, conversation, msgs)
        text = redact(text, [s for s in spans if chosen(s, pieces) == "redact"])
        code, line = upload_and_capture(host, token, repository, conversation, about, text.encode("utf-8"))
    except Unreachable as e:
        return FAILED, ["Blueprint is unreachable at %s (%s); nothing was sent. /blueprint-send retries." % (host, e)]
    except OSError as e:
        return FAILED, ["could not read the conversation (%s); nothing was sent" % e]
    if code == SENT:
        # A send is its person's yes, and each message's choice is kept: the session's end
        # sends it again, whole, those messages the same way and the rest checked afresh;
        # an edited text is final and is not sent again.
        mark(env, conversation)
        kept = "text" if text_file else "\n".join([""] + ["%s %s" % (c, m) for m, c in sorted(choices.items())])
        mark(env, conversation, "yes", kept)
    return code, [line]


def no_token(host):
    return ("no Blueprint sign-in for %s that blueprint-send can read (one kept in the OS keychain, the blueprint "
            "CLI's default, cannot be read here): run `! blueprint login --host %s --store file`, or set "
            "BLUEPRINT_ACCESS_TOKEN" % (host, host))


def consent(env, transcript, session_id):
    """(code, lines): the person's yes, recorded; SessionEnd sends the whole conversation."""
    if not (env.get("BLUEPRINT_CAPTURE_REPOSITORY") or "").strip():
        return FAILED, ["this repository does not capture conversations: its settings name no BLUEPRINT_CAPTURE_REPOSITORY; nothing was recorded"]
    conversation = session_id or (os.path.splitext(os.path.basename(transcript))[0] if transcript else "")
    if not conversation:
        return USAGE, ["blueprint-send --consent needs --session-id or --transcript"]
    mark(env, conversation)
    if edited(env, conversation) is None:  # a send's choices stay
        mark(env, conversation, "yes")
    return SENT, ["recorded the yes: this conversation goes to Blueprint's memory, whole, when this session ends, "
                  "the secret check first."]


def blocked(env, text, spans, transcript, conversation, msgs):
    """The warning and the three ways on, whose choice covers the messages it shows; the
    secret itself is never printed."""
    if msgs:
        mark(env, conversation, "shown", "\n".join(message for message, _ in msgs))
    edit = os.path.join(state_dir(env), re.sub(r"[^A-Za-z0-9._-]", "_", conversation) + ".txt")
    try:
        os.makedirs(state_dir(env), mode=0o700, exist_ok=True)
        fd = os.open(edit, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
    except OSError:
        edit = ""
    rules = sorted({rule for _, _, rule in spans})
    line = text.count("\n", 0, spans[0][0]) + 1
    again = "blueprint-send --transcript %s" % shlex.quote(transcript)
    lines = [
        "%s: %d match%s of %s, the first on line %d of the conversation. Nothing was sent." % (
            SECRET, len(spans), "" if len(spans) == 1 else "es", ", ".join(rules), line),
        "Ask the person which of the three:",
        "  Redact and send (each secret replaced by a marker): %s --redact" % again,
    ]
    if edit:
        lines.append("  Edit: change %s, then: %s --text %s" % (shlex.quote(edit), again, shlex.quote(edit)))
    lines += [
        "  Send anyway: %s --anyway" % again,
        "Sent text cannot be erased today.",
    ]
    return lines


# ---- the entry points -------------------------------------------------------

def ask(session_id):
    yes = "blueprint-send --consent --session-id %s" % shlex.quote(session_id)
    return ("blueprint: before you finish, ask the person, once and in one message: \"%s\" with a one-line summary "
            "of what this conversation was about. If they say yes, run `%s`: it records the yes, and the whole "
            "conversation is sent when this session ends, the secret check first. If they say no, send nothing: do "
            "not run it, and do not ask again in this session; /blueprint-send sends it any time." % (QUESTION, yes))


def leave_pending(env, repository, conversation, lines):
    """Keep a found secret for the next session in this repository to raise."""
    try:
        os.makedirs(pending_dir(env, repository), mode=0o700, exist_ok=True)
        fd = os.open(os.path.join(pending_dir(env, repository), slug(conversation) + ".json"),
                     os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"conversation": conversation, "lines": lines}, f)
    except OSError:
        return False
    return True


def raise_pending(env, repository):
    """Each pending secret of this repository, as an instruction to the agent, once."""
    folder = pending_dir(env, repository)
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith(".json"))
    except OSError:
        return
    for name in names:
        path = os.path.join(folder, name)
        try:
            with open(path, encoding="utf-8") as f:
                record = json.load(f)
            os.remove(path)
        except (OSError, ValueError):
            continue
        if not isinstance(record, dict) or not isinstance(record.get("lines"), list):
            continue
        print("blueprint: conversation %s, from an earlier session in this repository, was not sent to Blueprint's "
              "memory. Tell the person before anything else, in one message:" % record.get("conversation", "?"))
        print("\n".join(str(line) for line in record["lines"]))


def hook(env, stdin):
    try:
        payload = json.loads(stdin.read() or "{}")
    except ValueError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    repository = (env.get("BLUEPRINT_CAPTURE_REPOSITORY") or "").strip()
    mode = mode_of(env)
    if not repository or mode == "off":
        return 0
    event = payload.get("hook_event_name")
    session_id = payload.get("session_id") if isinstance(payload.get("session_id"), str) else ""
    transcript = payload.get("transcript_path") if isinstance(payload.get("transcript_path"), str) else ""
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else ""
    project = env.get("CLAUDE_PROJECT_DIR") or cwd or os.getcwd()
    if event == "SessionStart":
        if not unwatched(env, project, cwd):
            raise_pending(env, repository)
    elif event == "Stop" and mode == "ask":
        if payload.get("stop_hook_active") is True or not session_id or unwatched(env, project, cwd):
            return 0
        host, _ = target(env, project)
        if not host or os.path.exists(marker(env, session_id)):
            return 0
        mark(env, session_id)
        if not token_of(env, host):
            print("blueprint-send: not asking to send this conversation: " + no_token(host), file=sys.stderr)
            return 0
        print(json.dumps({"decision": "block", "reason": ask(session_id)}))
    elif event == "SessionEnd" and session_id and (mode == "always" or edited(env, session_id) is not None):
        if edited(env, session_id):
            print("blueprint-send: not sending this conversation again: it was sent as the person edited it.", file=sys.stderr)
            return 0
        code, lines = send(env, project, transcript, session_id)
        if code == BLOCKED:
            kept = leave_pending(env, repository, session_id, lines)
            again = "--transcript " + shlex.quote(transcript) if transcript else "--session-id " + shlex.quote(session_id)
            lines = ["%s %sRun blueprint-send %s to redact, edit or send anyway." % (
                lines[0], "The next session in this repository raises it. " if kept else "", again)]
        print("blueprint-send: " + lines[0], file=sys.stderr)
    return 0


def main(argv, env):
    if argv[:1] == ["hook"]:
        try:
            return hook(env, sys.stdin)
        except Exception as e:  # a hook never blocks work
            print("blueprint-send: the capture hook failed (%s); nothing was sent" % e, file=sys.stderr)
            return 0
    if argv[:1] != ["send"]:
        print("usage: blueprint-send [--transcript PATH | --session-id ID] [--text FILE] [--redact | --anyway | --consent]", file=sys.stderr)
        return USAGE
    opts, args = {"choice": ""}, argv[1:]
    while args:
        a = args.pop(0)
        if a in ("--transcript", "--session-id", "--text") and args:
            opts[a] = args.pop(0)
        elif a in ("--redact", "--anyway", "--consent"):
            opts["choice"] = a[2:]
        else:
            print("blueprint-send: unknown argument %s" % a, file=sys.stderr)
            return USAGE
    project = env.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if opts["choice"] == "consent":
        code, lines = consent(env, opts.get("--transcript", ""), opts.get("--session-id", ""))
        print("\n".join(lines))
        return code
    code, lines = send(env, project, opts.get("--transcript", ""), opts.get("--session-id", ""),
                       opts.get("--text", ""), opts["choice"])
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], dict(os.environ)))
