# Defines c4henv, which sets up the run-time environment of Code4hep in the
# current shell: for the development area containing $PWD (created by c4hinit),
# or for the release environment code4hep_env outside of an area. The setup is
# done by c4hruntime; c4henv.csh is the csh/tcsh counterpart.
#
# Usage: c4henv [--build-tree]
#   --build-tree  also put the area's build tree first, so that the freshly
#                 built libraries and plugins are used instead of the installed ones
c4henv() {
    local commands
    commands=$(c4hruntime --sh "$@") && eval "$commands"
}
