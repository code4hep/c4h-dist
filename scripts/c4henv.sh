# Defines c4henv, which sets up the run-time environment of Code4hep in the
# current shell: for the development area containing $PWD (created by c4hinit),
# or for the release environment code4hep_env outside of an area.
#
# Real installation prefixes are loaded rather than the environment view: both
# Stitched and Code4hep install lib/.edmplugincache, and a view keeps only one.
# Stitched's PluginManager reads the plugin caches of the LD_LIBRARY_PATH
# directories in order, and the first one that provides a plugin wins.
#
# Usage: c4henv [--build-tree]
#   --build-tree  also put the area's build tree first, so that tests use the
#                 freshly built libraries and plugins instead of the installed ones
c4henv() {
    local env=code4hep_env dir=$PWD prefix build
    while [ "$dir" != / ]; do
        if [ -e "$dir/.c4harea" ]; then
            env=$dir
            break
        fi
        dir=$(dirname "$dir")
    done

    . "${SPACK_ROOT:-/opt/spack}/share/spack/setup-env.sh"
    # also applies the run environment of the dependencies (ROOT, podio, DD4hep, ...)
    eval "$(spack -e "$env" load --sh code4hep)" || return
    # Spack does not set up Stitched's run-time environment by itself.
    . "$(spack -e "$env" location -i stitched)/bin/stitched_env.sh" >/dev/null

    prefix=$(spack -e "$env" location -i code4hep)
    export LD_LIBRARY_PATH=$prefix/lib:$LD_LIBRARY_PATH
    export PYTHONPATH=$prefix/python:$PYTHONPATH

    if [ "${1:-}" = --build-tree ]; then
        build=$(spack -e "$env" location -b code4hep)
        export LD_LIBRARY_PATH=$build/lib:$LD_LIBRARY_PATH
        export PYTHONPATH=$build/python:$PYTHONPATH
    fi
}
