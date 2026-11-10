#!@python@
# CloudStream downloads are often raw MPEG-TS with an .mp4 name. VLC's TS
# demuxer treats PID 4095 as the program map and then stops. The .vtt files
# beside those downloads are often HTML error pages, which VLC reports as a
# missing codec. FFmpeg demuxes the video. HTML sidecars are not autodetected.
import os
import sys
import urllib.parse

real = "@vlc@"
args = sys.argv[1:]

# Extensions VLC's subtitle autodetect probes in the same directory.
SUB_EXTS = (
    ".aqt",
    ".ass",
    ".idx",
    ".jss",
    ".mpl",
    ".psb",
    ".rt",
    ".sami",
    ".smi",
    ".srt",
    ".ssa",
    ".sub",
    ".sup",
    ".txt",
    ".vtt",
)


def local_path(arg):
    if arg.startswith("file://"):
        return urllib.parse.unquote(arg[7:])
    return arg


def first_bytes(path, count):
    try:
        with open(path, "rb") as handle:
            return handle.read(count)
    except OSError:
        return b""


def is_html(path):
    data = first_bytes(path, 64).lstrip()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:].lstrip()
    head = data[:24].lower()
    return head.startswith((b"<!doctype", b"<html", b"<?xml", b"<head"))


def html_sidecar(path):
    directory, name = os.path.split(path)
    stem, _ext = os.path.splitext(name)
    if not directory or not stem:
        return False
    try:
        names = os.listdir(directory)
    except OSError:
        return False
    prefix = stem.lower()
    for candidate in names:
        lowered = candidate.lower()
        if not lowered.startswith(prefix) or not lowered.endswith(SUB_EXTS):
            continue
        # "Episode 1" must not claim "Episode 10". VLC uses the same boundary.
        rest = lowered[len(prefix) :]
        if rest and rest[0] not in " .":
            continue
        sidecar = os.path.join(directory, candidate)
        if os.path.isfile(sidecar) and is_html(sidecar):
            return True
    return False


# Select the demuxer in the media URI so subtitle files keep their own reader.
# Unlike a global --demux, this also works when forwarding to an existing VLC.
user_set_demux = any(arg == "--demux" or arg.startswith("--demux=") for arg in args)

out = [real]
skip_subs = False
for index, arg in enumerate(args):
    if arg.startswith("-"):
        continue
    path = local_path(arg)
    if not os.path.isfile(path):
        continue
    if first_bytes(path, 1) == b"\x47" and not user_set_demux:
        args[index] = "file/avformat://" + urllib.parse.quote(os.path.abspath(path))
    if html_sidecar(path):
        skip_subs = True

if skip_subs and "--no-sub-autodetect-file" not in args:
    out.insert(1, "--no-sub-autodetect-file")
out.extend(args)

os.execv(real, out)
