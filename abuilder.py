#!python3

import argparse
import os
import sys

### global variables ###
upload_list = []
exec_cmds = []


### flags ###
BEFORE_BUILD = 0
AFTER_BUILD = 0


def main():
    parser = argparse.ArgumentParser(
        description='Build packages depend on params')

    parser.add_argument('-r', '--repo', metavar='repos', required=True,
                        dest='repos', action='append',
                        help='repo(s) to be updated after this build')

    # which package and which version to be builded
    parser.add_argument('-p', '--package', metavar='package', required=True,
                        dest='package', help='')

    # use the arch to determine the build environment
    parser.add_argument('-a', '--arch', metavar='arch', required=True,
                        dest='arch', help='arch of the build environment')

    parser.add_argument('-o', '--other', metavar='other', action='append',
                        dest='other', help='other build commands')

    args = parser.parse_args()

    # set the flags
    BEFORE_BUILD = 1
    AFTER_BUILD = 0

    # Use the collected arguments
    set_upload_repos(args.repos)
    set_howto_get_source(args.package)
    set_build_env(args.arch)
    set_build_cmds(args.other)


def set_upload_repos(repos):
    if BEFORE_BUILD and not upload_list and repos:
        upload_list = repos
    else:
        print("Set upload repos failed.")
        sys.exit(1)


def upload_debs():
    # only upload packages after the build process
    if AFTER_BUILD and not upload_list:
        for item in upload_list:
            pass
            # os.system("dput -uf " + item + "../*.changes")
    else:
        pass


def set_howto_get_source(package):
    pass


def set_build_env(arch):
    pass


def set_build_cmds(cmds):
    # parse all cmds to a list
    if not cmds:
        exec_cmds = cmds


def do_cmds():
    if not exec_cmds:
        for item in exec_cmds:
            os.system(item)


if __name__ == '__main__':
    main()
