#!/usr/bin/python

import sys
import os
import json 

#print("########################PARSERESULTS.PY########################")

GenScores = []
SimScores = []
TrigSimScores = []
RecoScores = []
TotalScores = []

MaxGen = 0
AvgGen = 0
MedGen = 0
MinGen = 1000000

MaxSim = 0
AvgSim = 0
MedSim = 0
MinSim = 1000000

MaxTrigSim = 0
AvgTrigSim = 0
MedTrigSim = 0
MinTrigSim = 1000000

MaxReco = 0
AvgReco = 0
MedReco = 0
MinReco = 1000000

MaxTotal = 0
AvgTotal = 0
MedTotal = 0
MinTotal = 1000000

# Each copy generates an output file
for i in range(0, int(os.environ['NCOPIES'])):
	filename = "proc_" + str(i + 1) + "/output"

	# The parser reports separately the time taken by event generation, simulation, trigger simulation, 
	# and reconstruction (and the total). Times are reported from many sub-modules; these keywords 
	# are used to make the groupings
	keywords = ["EvtGenInput", "Sum_Simulation", "Sum_TriggerSimulation", "SoftwareTrigger"]
	keepgoing = False;
	startintwo = False;

	Gen = 0
	Sim = 0
	TrigSim = 0
	Reco = 0
	Total = 0
	temptotal = 0

	with open(filename) as out:
		for line in out:

			# Flag to start parsing, initially false
			if keepgoing:
				splitline = line.split("|")
				#print splitline

				# Lines with Sum_ are the total time taken by the executable, not just
				# event processing calls
				if "Sum_" not in line:
					#print splitline
					temptotal = temptotal + float(splitline[3].strip())

				if splitline[0].strip() in keywords:
					if splitline[0].strip() == "EvtGenInput":
						Gen = float(splitline[3].strip())
						temptotal = 0
					elif splitline[0].strip() == "Sum_Simulation":
						Sim = temptotal
						temptotal = 0
					elif splitline[0].strip() == "Sum_TriggerSimulation":
						TrigSim = temptotal
						temptotal = 0
					elif splitline[0].strip() == "SoftwareTrigger":
						Reco = temptotal
						temptotal = 0
						keepgoing = False
			
				#print splitline[0].strip() + ": " + splitline[3].strip()

			# Almost there...
			if startintwo:
				keepgoing = True
				startintwo = False

			# This line is two lines before the part we care about, and is more distinctive
			# than the next line
			if "Name" in line and "Calls" in line:
				startintwo = True
				#print line	

			if "Total" in line: 
				Total = float(line.split("|")[3].strip())

	# Output is in seconds; convert to events / second
	Gen = float(os.environ['NEVENTS_THREAD']) / Gen
	Sim = float(os.environ['NEVENTS_THREAD']) / Sim
	TrigSim = float(os.environ['NEVENTS_THREAD']) / TrigSim
	Reco = float(os.environ['NEVENTS_THREAD']) / Reco
	Total = float(os.environ['NEVENTS_THREAD']) / Total

	#print "Gen: " + str(Gen)
	#print "Sim: " + str(Sim)
	#print "TrigSim: " + str(TrigSim)
	#print "Reco: " + str(Reco)
	#print "Total: " + str(Total)

	GenScores.append(Gen)
	SimScores.append(Sim)
	TrigSimScores.append(TrigSim)
	RecoScores.append(Reco)
	TotalScores.append(Total)

	#print GenScores
	#print SimScores
	#print TrigSimScores
	#print RecoScores
	#print TotalScores

	if Gen > MaxGen:
		MaxGen = Gen
	if Sim > MaxSim:
		MaxSim = Sim
	if TrigSim > MaxTrigSim:
		MaxTrigSim = TrigSim
	if Reco > MaxReco:
		MaxReco = Reco
	if Total > MaxTotal:
		MaxTotal = Total

	if Gen < MinGen:
		MinGen = Gen
	if Sim < MinSim:
		MinSim = Sim
	if TrigSim < MinTrigSim:
		MinTrigSim = TrigSim
	if Reco < MinReco:
		MinReco = Reco
	if Total < MinTotal:
		MinTotal = Total

	AvgGen = AvgGen + Gen / float(os.environ['NCOPIES'])
	AvgSim = AvgSim + Sim / float(os.environ['NCOPIES'])
	AvgTrigSim = AvgTrigSim + TrigSim / float(os.environ['NCOPIES'])
	AvgReco = AvgReco + Reco / float(os.environ['NCOPIES'])
	AvgTotal = AvgTotal + Total / float(os.environ['NCOPIES'])


GenScores.sort()
SimScores.sort()
TrigSimScores.sort()
RecoScores.sort()
TotalScores.sort()

if len(GenScores) % 2 == 0:
	MedGen = (GenScores[len(GenScores) / 2] + GenScores[len(GenScores) / 2 - 1]) / 2.0
	MedSim = (SimScores[len(SimScores) / 2] + SimScores[len(SimScores) / 2 - 1]) / 2.0
	MedTrigSim = (TrigSimScores[len(TrigSimScores) / 2] + TrigSimScores[len(TrigSimScores) / 2 - 1]) / 2.0
	MedReco = (RecoScores[len(RecoScores) / 2] + RecoScores[len(RecoScores) / 2 - 1]) / 2.0
	MedTotal = (TotalScores[len(TotalScores) / 2] + TotalScores[len(TotalScores) / 2 - 1]) / 2.0
else:
	MedGen = GenScores[len(GenScores) / 2]
	MedSim = SimScores[len(SimScores) / 2]
	MedTrigSim = TrigSimScores[len(TrigSimScores) / 2]
	MedReco = RecoScores[len(RecoScores) / 2]
	MedTotal = TotalScores[len(TotalScores) / 2]


OutputJSON = {}
OutputJSON['run_info'] = {}
OutputJSON['report'] = {}
OutputJSON['report']['wl-scores'] = {}
OutputJSON['report']['wl-stats'] = {}
OutputJSON['report']['wl-stats']['throughput_score'] = {}
OutputJSON['app'] = {}

OutputJSON['run_info']['copies'] = int(os.environ['NCOPIES'])
OutputJSON['run_info']['threads_per_copy'] = int(os.environ['NTHREADS'])
OutputJSON['run_info']['events_per_thread'] = int(os.environ['NEVENTS_THREAD'])
OutputJSON['report']['wl-scores']['gen'] = AvgGen
OutputJSON['report']['wl-scores']['sim'] = 1.0 / (1.0 / AvgSim + 1.0 / AvgTrigSim)
OutputJSON['report']['wl-scores']['reco'] = AvgReco
OutputJSON['report']['wl-scores']['gen-sim-reco'] = AvgTotal
OutputJSON['report']['wl-stats']['throughput_score']['avg'] = AvgTotal
OutputJSON['report']['wl-stats']['throughput_score']['median'] = MedTotal
OutputJSON['report']['wl-stats']['throughput_score']['min'] = MinTotal
OutputJSON['report']['wl-stats']['throughput_score']['max'] = MaxTotal
OutputJSON['report']['wl-stats']['throughput_score']['count'] = int(os.environ['NCOPIES'])
OutputJSON['app']['version'] = "v1.0"
OutputJSON['app']['description'] = "Belle-2 generation, simulation, and reconstruction of BBbar events based on release 05-01-05"

OutputFile = open("belle2-gen-sim-reco_summary.json", "w")
json.dump(OutputJSON, OutputFile)
OutputFile.close()
