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

    parser.add_argument('-s', '--source', metavar='source', required=True,
                        dest='source', help='source code git address')

    args = parser.parse_args()

    # set the flags
    BEFORE_BUILD = 1
    AFTER_BUILD = 0

    # Use the collected arguments
    set_upload_repos(args.repos)


def set_upload_repos(repos):
    if BEFORE_BUILD and not upload_list and repos:
        for item in repos:
            upload_list.append(item)
    else:
        print("Initial upload repos failed")
        sys.exit(1)


def upload_debs():
    # only upload packages after the build process
    if AFTER_BUILD and not upload_list:
        for item in upload_list:
            os.system("dput -uf " + item + "../*.changes")
    else:
        pass


if __name__ == '__main__':
    main()

