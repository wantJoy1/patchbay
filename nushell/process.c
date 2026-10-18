#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "moonbit.h"

extern char **environ;

typedef struct {
  FILE *in;
  FILE *out;
  int eof;
} process;

static process processes[16];
static int count;

// `args` holds the arguments separated by NUL bytes.
MOONBIT_FFI_EXPORT int32_t patchbay_spawn(moonbit_bytes_t args) {
  int32_t n = Moonbit_array_length(args);
  char *buf = malloc(n + 1);
  memcpy(buf, args, n);
  buf[n] = 0;
  char *argv[16];
  int argc = 0;
  for (char *s = buf; s < buf + n + 1 && argc < 15; s += strlen(s) + 1) argv[argc++] = s;
  argv[argc] = NULL;
  int to[2], from[2];
  if (count == 16 || pipe(to) || pipe(from)) return -1;
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, to[0], 0);
  posix_spawn_file_actions_adddup2(&actions, from[1], 1);
  posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
  posix_spawn_file_actions_addclose(&actions, to[1]);
  posix_spawn_file_actions_addclose(&actions, from[0]);
  pid_t pid;
  int failed = posix_spawnp(&pid, argv[0], &actions, NULL, argv, environ);
  posix_spawn_file_actions_destroy(&actions);
  free(buf);
  close(to[0]);
  close(from[1]);
  if (failed) return -1;
  processes[count] = (process){fdopen(to[1], "w"), fdopen(from[0], "r"), 0};
  return count++;
}

MOONBIT_FFI_EXPORT void patchbay_write_line(int32_t p, moonbit_bytes_t line) {
  fwrite(line, 1, Moonbit_array_length(line), processes[p].in);
  fputc('\n', processes[p].in);
  fflush(processes[p].in);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t patchbay_read_line(int32_t p) {
  char *line = NULL;
  size_t cap = 0;
  ssize_t n = getline(&line, &cap, processes[p].out);
  processes[p].eof = n < 0;
  if (n > 0 && line[n - 1] == '\n') n--;
  moonbit_bytes_t b = moonbit_make_bytes(n < 0 ? 0 : n, 0);
  if (n > 0) memcpy(b, line, n);
  free(line);
  return b;
}

MOONBIT_FFI_EXPORT int32_t patchbay_at_eof(int32_t p) {
  return processes[p].eof;
}
