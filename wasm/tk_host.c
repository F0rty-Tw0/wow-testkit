/* The Lua state of the browser host: stock Lua 5.1.5 plus the __tk_fs bridge fs.lua calls (tools/run51.py is the
 * Python twin) and the five entry points host/worker.js reaches through ccall. Everything else is kit Lua: the
 * bootstrap below only wires SessionHost's JSON methods to the entry points. */
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

static lua_State *L;

/* Every function the host defines for the entry points answers JSON; none raises. */
static const char *BOOTSTRAP =
    "package.path = '/kit/?.lua;/kit/?/init.lua'\n"
    "local Json = require('json')\n"
    "local SessionHost = require('session_host')\n"
    "local host\n"
    "local function failure(err) return Json.encode({ ok = false, error = tostring(err) }) end\n"
    "local function guard(fn)\n"
    "  return function(...)\n"
    "    local ok, reply = pcall(fn, ...)\n"
    "    return ok and reply or failure(reply)\n"
    "  end\n"
    "end\n"
    "__tk_open = guard(function(optsJson)\n"
    "  host = SessionHost.new(Json.decode(optsJson))\n"
    "  return host:handleJson('info', '{}')\n"
    "end)\n"
    "__tk_call = guard(function(method, reqJson)\n"
    "  return host and host:handleJson(method, reqJson) or failure('not open')\n"
    "end)\n"
    "__tk_drain = guard(function() return host and host:drain() or '[]' end)\n"
    "__tk_shutdown = function() if host then pcall(host.shutdown, host) end end\n";

static int fail_path(lua_State *state, const char *path) {
  return luaL_error(state, "%s: %s", path, strerror(errno));
}

/* Sorted names in a directory, without . and ..; raises on a missing directory as os.listdir does. */
static int fs_list(lua_State *state) {
  const char *path = luaL_checkstring(state, 1);
  struct dirent **entries;
  int count = scandir(path, &entries, NULL, alphasort);
  if (count < 0) {
    return fail_path(state, path);
  }
  lua_newtable(state);
  int n = 0;
  for (int i = 0; i < count; i++) {
    const char *name = entries[i]->d_name;
    if (strcmp(name, ".") != 0 && strcmp(name, "..") != 0) {
      lua_pushstring(state, name);
      lua_rawseti(state, -2, ++n);
    }
    free(entries[i]);
  }
  free(entries);
  return 1;
}

static int fs_exists(lua_State *state) {
  struct stat info;
  lua_pushboolean(state, stat(luaL_checkstring(state, 1), &info) == 0);
  return 1;
}

static int is_dir(const char *path) {
  struct stat info;
  return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static int fs_isdir(lua_State *state) {
  lua_pushboolean(state, is_dir(luaL_checkstring(state, 1)));
  return 1;
}

/* os.makedirs(path, exist_ok=True): every missing level, nothing raised when the folder is already there. */
static int fs_mkdirp(lua_State *state) {
  const char *path = luaL_checkstring(state, 1);
  char *copy = strdup(path);
  for (char *at = copy + 1; *at; at++) {
    if (*at == '/') {
      *at = '\0';
      mkdir(copy, 0777);
      *at = '/';
    }
  }
  free(copy);
  if (mkdir(path, 0777) != 0 && !is_dir(path)) {
    return fail_path(state, path);
  }
  return 0;
}

/* One level: true when this call made it, false when it already existed; a missing parent raises. */
static int fs_mkdir(lua_State *state) {
  const char *path = luaL_checkstring(state, 1);
  if (mkdir(path, 0777) == 0) {
    lua_pushboolean(state, 1);
  } else if (errno == EEXIST) {
    lua_pushboolean(state, 0);
  } else {
    return fail_path(state, path);
  }
  return 1;
}

/* os.replace: rename(2) replaces an existing target atomically. */
static int fs_replace(lua_State *state) {
  const char *from = luaL_checkstring(state, 1);
  if (rename(from, luaL_checkstring(state, 2)) != 0) {
    return fail_path(state, from);
  }
  return 0;
}

static const luaL_Reg FS_FUNCTIONS[] = {
    {"list", fs_list}, {"exists", fs_exists}, {"isdir", fs_isdir},
    {"mkdirp", fs_mkdirp}, {"mkdir", fs_mkdir}, {"replace", fs_replace},
    {NULL, NULL},
};

/* 0, or 1 with the reason on stderr. */
int tk_init(void) {
  if (L) {
    return 0;
  }
  L = luaL_newstate();
  luaL_openlibs(L);
  lua_newtable(L);
  luaL_register(L, NULL, FS_FUNCTIONS);
  lua_setglobal(L, "__tk_fs");
  if (luaL_dostring(L, BOOTSTRAP)) {
    fprintf(stderr, "tk_init: %s\n", lua_tostring(L, -1));
    return 1;
  }
  return 0;
}

/* Calls the global fn with the strings args and keeps its string result in the registry, so the pointer stays valid
 * until the next call. */
static const char *run(const char *fn, const char *first, const char *second) {
  if (!L) {
    return "{\"ok\":false,\"error\":\"tk_init has not run\"}";
  }
  lua_getglobal(L, fn);
  int nargs = 0;
  if (first) {
    lua_pushstring(L, first);
    nargs++;
  }
  if (second) {
    lua_pushstring(L, second);
    nargs++;
  }
  if (lua_pcall(L, nargs, 1, 0) != 0) {
    lua_pop(L, 1);
    lua_pushstring(L, "{\"ok\":false,\"error\":\"tk_host: entry point failed\"}");
  }
  lua_setfield(L, LUA_REGISTRYINDEX, "tk_result");
  lua_getfield(L, LUA_REGISTRYINDEX, "tk_result");
  const char *text = lua_tostring(L, -1);
  lua_pop(L, 1);
  return text;
}

/* SessionHost.new(decoded optsJson), then its info reply; { "ok": false, "error" } when that fails. */
const char *tk_open(const char *optsJson) {
  return run("__tk_open", optsJson, NULL);
}

const char *tk_call(const char *method, const char *reqJson) {
  return run("__tk_call", method, reqJson);
}

/* The events since the last drain as a JSON array; "[]" before tk_open. */
const char *tk_drain(void) {
  return run("__tk_drain", NULL, NULL);
}

void tk_shutdown(void) {
  if (!L) {
    return;
  }
  lua_getglobal(L, "__tk_shutdown");
  lua_pcall(L, 0, 0, 0);
}
