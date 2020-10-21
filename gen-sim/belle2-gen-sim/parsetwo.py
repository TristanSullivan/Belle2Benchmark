#!/usr/bin/python

#print "___________________________________PARSETWO___________________________________"

import sys

if len(sys.argv) < 2:
	print "Usage: pass number of copies processed as argument"
	sys.exit()


copies = int(sys.argv[1])

score = 0

for i in range(copies):
	filename = "../proc_" + str(i + 1) + "/parsedoutput"
	for line in file(filename):
		score = score + float(line.split()[0])
		#print i

print score 
