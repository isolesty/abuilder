#!/usr/bin/env python3
'''Get all repos of a user from gogs'''

import urllib.request
from bs4 import BeautifulSoup

IP = "ip address"
USERNAME = "username"

BASEURL = IP + USERNAME + '?page=%s'
MAXURL = BASEURL % 999999
maxpage = 0

packages_list = []

LOG_LEVEL = ''
# LOG_LEVEL = 'detail'


maxreq = urllib.request.Request(MAXURL)
response = urllib.request.urlopen(maxreq)

# get the maxpage
maxsoup = BeautifulSoup(response, "lxml")

maxpage = int(maxsoup.find(class_="active item").text)

if LOG_LEVEL == 'detail':
    print(maxpage)

# get each page
for x in range(1, maxpage + 1):
    if LOG_LEVEL == 'detail':
        print("Get packages page: " + x)

    req = urllib.request.Request(BASEURL % x)
    response = urllib.request.urlopen(req)

    soupx = BeautifulSoup(response, "lxml")

    for item in soupx.find_all(class_="name"):
        if LOG_LEVEL == 'detail':
            print(item.text)
        packages_list.append(item.text)

# uniq packages_list and print
for package in list(set(packages_list)):
    print(package)
