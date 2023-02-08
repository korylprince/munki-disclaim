# About

## The Problem

macOS Ventura (13.x) introduced new [privacy controls for app management](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services/identity?language=objc). Apps without this permission can't update other applications in certain situations. This usually isn't a problem because signed pkgs/apps can be updated if the signer is the same for both versions.

macOS has the concept of the "responsible" process. This is the process which the TCC framework "pins" responsibility to in a process tree that tries to do something that needs permissions. In other words, the responsible process is the one you see in System Preferences' Privacy & Security permissions panes. *Note: executable names may not always show as you'd expect due to how the preference pane follows symlinks. e.g. python3 may show instead of munki-python*

Since Munki is written in Python, it has additional challenges when trying to updated these unsigned apps/pkgs. We can take a look at an example process tree to illustrate this:

```
launchd
  - .../munki-python .../supervisor
    - .../munki-python .../managedsoftwareupdate
```

`launchd` "disclaims" responsibility for all of the processes it starts, so in this example, responsibility falls on the top level `munki-python` process. If managedsoftwarecenter tries to update an app that triggers the `SystemPolicyAppBundles` permssion, the TCC framework will look at the permissions for `munki-python`, not `managedsoftwareupdate`.

Granting permissions (through a profile or manually in System Preferences) to a child process (e.g. `managedsoftwareupdate`) does *not* cause the TCC framework to stop the permissions check from "bubbling" up to the responsible process; permissions must be set on the responsible process.

Munki can be run in several different ways, and this results in different responsible processes:

* Running managedsoftwareupdate over SSH causes sshd-keygen-wrapper to be the responsible process
* Running managedsoftwareupdate in Terminal.app causes Terminal.app to be the responsible process
* Running Managed Software Center.app or the background supervisor causes munki-python (python3) to be the responsible process

## The Solution

Fortunately, there is a solution. Apple has a private API that allows a parent process to "disclaim" a child process. This causes responsibility to stop at the child process. This is used by many applications (Chrome, Firefox, Code Editors, etc) to allow child processes to manage their own permissions. For a more in-depth view of the problem and solution, see [this blog post](https://www.qt.io/blog/the-curious-case-of-the-responsible-process) by a QT developer.

The solution for Munki is to have a shim executable insert itself into the process tree:

```
launchd
  - .../munkishim (symlinked as .../managedsoftwareupate)
    - .../munkishim (disclaimed child)
      - .../munki-python .../supervisor
        - .../munki-python .../managedsoftwareupdate.py
```

`munkishim` executes itself so the child process can be disclaimed. This causes `munkishim` (the child) to be the responsible process, so all permissions can be assigned to the `munkishim` executable, no matter how Munki is being called.

This allows a single, new, executable to be added to `/usr/local/munki` and the python scripts are replaced with symlinks:

* mv /usr/local/munki/managedsoftwareupdate /usr/local/munki/managedsoftwareupdate
* ln -s /usr/local/munki/munkishim /usr/local/munki/managedsoftwareupdate

# Building

Run `sh ./build.sh` to build an unsigned universal binary, or run `sh ./build.sh adhoc` to build an adhoc-signed universal binary (see Signing).

# Signing

It's recommended to sign `munkishim` so a single profile can be used to assign permissions that won't need to be updated every time the shim is built/updated.

`codesign --sign "Name of your Developer ID Application certificate in Keychain Access" --identifier "tld.domain.your.id" build/munkishim`

You can also use an ad hoc signature for testing, but the CodeRequirement changes each time the binary changes.

Use `codesign -d -r - build/munkishim` to obtain the CodeRequirement for your profile (see Profile).

# Install

Run `sudo sh ./install.sh` to download and install the current (as of this writing) stable version of Munki, install it, and then install the shim over it.

This also installs a modified version of `pkg.py` from the special-built pkg from [here](https://groups.google.com/g/munki-dev/c/hFy4y4g4okc). This modified version calls `installer` directly via a subprocess (so that it stays in the process tree) instead of launching a launchd job like Munki currently does. *Note: this took **forever** for me to find.*

# Profile

To actually grant permissions to the shim, you'll need to install a profile with a `com.apple.TCC.configuration-profile-policy`.`SystemPolicyAppBundles` payload with:

* Identifier: /usr/local/munki/munkishim
* IdentifierType: path
* CodeRequirement: output of `codesign -d -r - /usr/local/munki/munkishim`
* Allowed: true

For an example profile see the [here](https://groups.google.com/g/munki-dev/c/hFy4y4g4okc).
