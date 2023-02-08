#include <libgen.h>
#include <signal.h>
#include <spawn.h>
#include <string>
#include <unistd.h>

extern "C" {
    int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t attrs, int disclaim)
        __attribute__((availability(macos,introduced=10.14), weak_import));
}

#define POSIX_CHECK(expr) \
    if (int err = (expr)) { \
        exit(err); \
    }

const char *shimmed_flg = "--shimmed";
const char *munki_python_path = "/usr/local/munki/munki-python";

const std::string allowed_cmds[] = {"appusaged", "app_usage_monitor", "authrestartd", "launchapp", "logouthelper", "managedsoftwareupdate", "supervisor"};

int main(int argc, char * const argv[], char *const *envp) {
    // if shimmed, exec python
    if (argc > 1 && strcmp(argv[1], shimmed_flg) == 0) {
        // check command is allowed    
        char *cmd = basename(strdup(argv[0]));
        if (std::find(std::begin(allowed_cmds), std::end(allowed_cmds), cmd) == std::end(allowed_cmds)) {    
            printf("Unknown cmd: %s\n", argv[0]);     
            exit(EPERM);    
        }

        // check path is absolute
        char *abs_path;
        asprintf(&abs_path, "/usr/local/munki/%s", cmd);
        if (strcmp(argv[0], abs_path) != 0) {
            printf("Unknown path: %s\n", argv[0]);     
            exit(EPERM);    
        }

        // copy args and replace ".../{cmd} --shimmed" with ".../munki-python .../{cmd}.py"
        char **new_argv = (char **)malloc((argc+1) * sizeof(char *));
        new_argv[0] = strdup(munki_python_path);
        char *new_path;
        asprintf(&new_path, "%s.py", argv[0]);
        new_argv[1] = new_path;
        if (argc > 2) {
            for (int i = 2; i <= argc; i++)
                new_argv[i] = argv[i];
        }

        // exec python script
        if (execvp(new_argv[0], &new_argv[0]) == -1) {
            return errno;
        }
        return 0;
    }
    // otherwise exec shimmed self
     
    // set argv to "--shimmed" + argv
    char **new_argv = (char **)malloc((argc+2) * sizeof(char *));
    new_argv[0] = strdup(argv[0]);
    new_argv[1] = strdup(shimmed_flg);
    if (argc > 1) {
        for (int i = 1; i <= argc; i++)
            new_argv[i+1] = argv[i];
    }
    
    // init posix attr
    posix_spawnattr_t attr;
    POSIX_CHECK(posix_spawnattr_init(&attr));

    // act like execve(2)
    short flags = POSIX_SPAWN_SETEXEC;

    // reset signal mask
    sigset_t sig_mask;
    sigemptyset(&sig_mask);
    POSIX_CHECK(posix_spawnattr_setsigmask(&attr, &sig_mask));
    flags |= POSIX_SPAWN_SETSIGMASK;

    // reset signals to default behavior
    sigset_t sig_default;
    sigfillset(&sig_default);
    POSIX_CHECK(posix_spawnattr_setsigdefault(&attr, &sig_default));
    flags |= POSIX_SPAWN_SETSIGDEF;

    // set flags
    POSIX_CHECK(posix_spawnattr_setflags(&attr, flags));

    // force TCC responsibility on child
    if (@available(macOS 10.14, *))
        POSIX_CHECK(responsibility_spawnattrs_setdisclaim(&attr, 1));

    // exec shimmed process
    int err = posix_spawn(NULL, argv[0], NULL, &attr, new_argv, envp);

    // clean up attr
    posix_spawnattr_destroy(&attr);

    return err;
}
