#!python3

import argparse
import os
import sys

### global variables ###
upload_list = []


### flags ###
BEFORE_BUILD = 0
AFTER_BUILD = 0


def main():
    parser = argparse.ArgumentParser(
        description='Build packages depend on params')

    parser.add_argument('-r', '--repo', metavar='repos', required=True,
                        dest='repos', action='append',
                        help='repo(s) to be updated after this build')

    # get the git source and commit id from command line
    parser.add_argument('-s', '--source', metavar='source', required=True,
                        dest='source', help='source code git address')
    parser.add_argument('-c', '--commit', metavar='commit', required=True,
                        dest='commit', help='commit to be builded')

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
    set_howto_get_source(args.source, args.commit)
    set_build_env(args.arch)


def set_upload_repos(repos):
    if BEFORE_BUILD and not upload_list and repos:
        for item in repos:
            upload_list.append(item)
    else:
        print("Set upload repos failed.")
        sys.exit(1)


def upload_debs():
    # only upload packages after the build process
    if AFTER_BUILD and not upload_list:
        for item in upload_list:
            os.system("dput -uf " + item + "../*.changes")
    else:
        pass


def set_howto_get_source(source, commit):
    pass


def set_build_env(arch):
    pass


if __name__ == '__main__':
    main()
