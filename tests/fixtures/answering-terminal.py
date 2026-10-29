# answering-terminal.py <out> <keys-json> <command...>
# Runs the command on a pty that plays a real terminal: it answers colour (OSC 10/11) and
# cursor-position (DSR 6n) queries on the program's input, as Ghostty does, and types the
# keys from <keys-json>, a list of [seconds to wait, text]. Everything the program put on the
# screen, tty echo included, is written to <out>. The screen is 40 rows by 100 columns.
import fcntl, json, os, pty, select, signal, struct, sys, termios, time

out, keys, cmd = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3:]
answers = {
    b"\x1b]10;?\x1b\\": b"\x1b]10;rgb:cdcd/d6d6/f4f4\x1b\\",
    b"\x1b]11;?\x1b\\": b"\x1b]11;rgb:2828/2c2c/3434\x1b\\",
    b"\x1b[6n": b"\x1b[74;25R",
}
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))

screen, pending = b"", b""
plan = [(time.time() + sum(k[0] for k in keys[: i + 1]), k[1].encode()) for i, k in enumerate(keys)]
deadline = (plan[-1][0] if plan else time.time()) + 3
while time.time() < deadline:
    if plan and time.time() >= plan[0][0]:
        os.write(fd, plan.pop(0)[1])
    ready, _, _ = select.select([fd], [], [], 0.02)
    if not ready:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    screen += data
    pending += data
    for query, answer in answers.items():
        while query in pending:
            pending = pending.replace(query, b"", 1)
            os.write(fd, answer)
    pending = pending[-16:]
try:
    os.kill(pid, signal.SIGTERM)
except ProcessLookupError:
    pass
open(out, "wb").write(screen.replace(b"\r", b""))
