#!python3

import argparse


def main():
    parser = argparse.ArgumentParser(
        description='Build packages in one build environment')

    parser.add_argument('-r', '--repo', metavar='repos', required=True,
                        dest='repos', action='append',
                        help='repo(s) to be updated after this build')

    args = parser.parse_args()
    # Use the collected arguments
    dputto(args.repos)


def dputto(repos):
    for item in repos:
        print(item)

if __name__ == '__main__':
    main()
