#ifndef HN_UTILS_OS
#define HN_UTILS_OS

/* libc bindings. The HolyC `Write`/`"..."` printf paths buffer and use
 * non-Linux syscall numbers, so all protocol I/O goes through libc directly. */
extern "c" I64 read(I32 fd, U0 *buf, U64 n);
extern "c" I64 write(I32 fd, U0 *buf, U64 n);
extern "c" U8 *getenv(U8 *name);
extern "c" I32 getpid();
extern "c" I32 chmod(U8 *path, U32 mode);
extern "c" I32 unlink(U8 *path);
extern "c" I32 access(U8 *path, I32 mode);
extern "c" I32 mkstemp(U8 *tmpl);
extern "c" I32 close(I32 fd);
extern "c" U0 exit(I32 status);

#define FD_STDIN   0
#define FD_STDOUT  1
#define FD_STDERR  2

#define F_OK 0
#define R_OK 4
#define W_OK 2

#define MODE_0600 0x180 /* rw------- */
#define MODE_0644 0x1A4 /* rw-r--r-- */
#define MODE_0700 0x1C0 /* rwx------ */
#define MODE_0755 0x1ED /* rwxr-xr-x */

Bool PathExists(U8 *path)
{
  if (!path) return FALSE;
  return access(path, F_OK) == 0;
}


U8 *ReadFdFile(U8 *path, I64 *out_len)
{
  *out_len = 0;
  I32 fd = open(path, O_RDONLY);
  if (fd < 0) return NULL;

  I64 cap = 65536;
  I64 len = 0;
  U8 *buf = MAlloc(cap);
  while (TRUE) {
    if (len + 1024 > cap) {
      cap = cap * 2;
      U8 *nb = MAlloc(cap);
      MemCpy(nb, buf, len);
      Free(buf);
      buf = nb;
    }
    I64 n = read(fd, buf + len, cap - len - 1);
    if (n <= 0) break;
    len += n;
  }
  close(fd);
  buf[len] = 0;
  *out_len = len;
  return buf;
}


Bool WriteFdFile(U8 *path, U8 *data, I64 len, I64 mode=MODE_0644)
{
  if (!path) return FALSE;
  I32 fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, mode);
  if (fd < 0) return FALSE;

  I64 written = 0;
  while (written < len) {
    I64 n = write(fd, data + written, len - written);
    if (n <= 0) { close(fd); return FALSE; }
    written += n;
  }
  close(fd);
  return TRUE;
}

I64 g_shell_seq = 0;


U8 *ShellCapture(U8 *cmd, I64 *out_len)
{
  *out_len = 0;
  g_shell_seq++;
  U8 *dir = StrPrint(NULL, "/tmp/holy-nano-mcp-sh-%d-%d", getpid(), g_shell_seq);
  MkDir(dir, MODE_0700, TRUE);
  chmod(dir, MODE_0700);

  U8 *out_path = StrPrint(NULL, "%s/out.txt", dir);
  U8 *full = StrPrint(NULL, "%s > %s 2>/dev/null", cmd, out_path);
  System(full);
  chmod(out_path, MODE_0600);

  I64 len = 0;
  U8 *raw = ReadFdFile(out_path, &len);

  U8 *cleanup = StrPrint(NULL, "rm -rf %s", dir);
  System(cleanup);

  Free(cleanup);
  Free(full);
  Free(out_path);
  Free(dir);

  if (!raw) return NULL;
  *out_len = len;
  return raw;
}

/* File permission bits as an integer, e.g. 600. -1 when unknown. */
I64 FileModeBits(U8 *path)
{
  U8 *cmd = StrPrint(NULL, "stat -c %%a %s", path);
  I64 len = 0;
  U8 *out = ShellCapture(cmd, &len);
  Free(cmd);
  if (!out) return -1;
  I64 mode = -1;
  if (len > 0) mode = Atoi(out);
  Free(out);
  return mode;
}

/* TRUE when the file is readable only by its owner. */
Bool FileIsOwnerOnly(U8 *path)
{
  I64 mode = FileModeBits(path);
  if (mode < 0) return FALSE;
  /* stat prints octal digits as decimal, so group/other are the last two. */
  return mode % 100 == 0;
}

/* Reads a whole env var, returning NULL for unset *and* empty. */
U8 *EnvOrNull(U8 *name)
{
  U8 *v = getenv(name);
  if (!v || v[0] == '\0') return NULL;
  return v;
}

#endif
