#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Descriptor: mixed_BBbar

#############################################################
# Steering file for official MC production of early phase 3
# 'mixed' BBbar samples without beam backgrounds (BGx0).
#
# August 2019 - Belle II Collaboration
#############################################################

import basf2 as b2
import generators as ge
import simulation as si
import L1trigger as l1
import reconstruction as re
from ROOT import Belle2
import glob as glob

b2.set_random_seed(12345)

# background (collision) files
#bg = glob.glob('/group/belle2/users/jbennett/BG/early_phase3/prerelease-04-00-00a/overlay/phase31/BGx1/set0/*.root') # if you run at KEKCC
#RJS bg = glob.glob('./BGforOverlay*.root')

# set database conditions (in addition to default)
b2.conditions.reset()
b2.conditions.prepend_globaltag("mc_production_MC13a_rev1")

#: number of events to generate, can be overriden with -n
num_events = 10
#: output filename, can be overriden with -o
output_filename = "mdst.root"

# create path
main = b2.create_path()

# specify number of events to be generated
main.add_module("EventInfoSetter", expList=1003, runList=0, evtNumList=num_events)

# generate BBbar events
ge.add_evtgen_generator(main, finalstate='mixed')

# detector simulation
si.add_simulation(main)

# trigger simulation
l1.add_tsim(main, Belle2Phase="Phase3")

# reconstruction
#RJS 
re.add_reconstruction(main)

# Finally add mdst output
#RJS re.add_mdst_output(main, filename=output_filename)

# process events and print call statistics
b2.process(main)
print(b2.statistics)
