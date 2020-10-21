#!/usr/bin/python

import sys

if len(sys.argv) < 2:
	print "Usage: pass number of events processed as argument"
	sys.exit()


events = float(sys.argv[1])

time = 0

for line in file("output"):
	if "Total" in line:
		if time > 0:
			print "More than one output found! Run bad"
		else:	
			time = time + float(line.split()[8])			
		

print events / time
