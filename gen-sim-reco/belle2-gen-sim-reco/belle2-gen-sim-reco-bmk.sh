#!/bin/bash

#set -x # enable debug printouts

#set -e # immediate exit on error

# Function parseResults must be defined in each benchmark (or in a separate file parseResults.sh)
# [NB: if a separate function generateSummary exists, it must be internally called by parseResults]
# Input argument $1: status code <fail> from validateInputArguments and doOne steps:
# - <fail> < 0: validateInputArguments failed
# - <fail> > 0: doOne failed (<fail> processes failed out of $NCOPIES)
# - <fail> = 0: OK
# Return value: please return 0 if parsing was successful, 1 otherwise
# The following variables are guaranteed to be defined and exported: NCOPIES, NTHREADS, NEVENTS_THREAD, BMKDIR, DEBUG
# Logfiles have been stored in process-specific working directories <basewdir>/proc_<1...NCOPIES>
# The function is started in the base working directory <basewdir>:
# please store here the overall json summary file for all NCOPIES processes combined
function parseResults(){
  if [ "$1" == "" ] || [ "$2" != "" ]; then echo "[parseresults] ERROR! Invalid arguments '$@' to parseResults"; return 1; fi
  echo "[parseResults] parse results and generate summary (previous status: $1)"
  #local score=1 # hardcoded (dummy)
  local msg="OK"
  #local app="\"UNKNOWN\""
  local app="\"belle2-gen-sim-reco-bmk\""
  local json=belle2-gen-sim-reco_summary.json
  cd proc_1
  python parsetwo.py $NCOPIES > score
  #cat score
  cd ..
  #cat proc_1/score
  #for i in $(seq $NCOPIES); do echo $i; ls proc_$i; cat proc_$i/parsedoutput; done
  #python parsetwo.py $NCOPIES > score
  local score=`cat proc_1/score`
  echo -e "{ \"copies\" : $NCOPIES , \"threads_per_copy\" : $NTHREADS , \"events_per_thread\" : $NEVENTS_THREAD , \"throughput_score\" : $score , \"log\": \"$msg\", \"app\" : ${app} }" > ${json} && cat ${json}
  # Return 0 if parsing was successful, 1 otherwise
  return 0
}

# Function doOne must be defined in each benchmark
# Input argument $1: process index (between 1 and $NCOPIES)
# Return value: please return 0 if this workload copy was successful, 1 otherwise
# The following variables are guaranteed to be defined and exported: NCOPIES, NTHREADS, NEVENTS_THREAD, BMKDIR, DEBUG
# The function is started in process-specific working directory <basewdir>/proc_$1:
# please store here the individual log files for each of the NCOPIES processes
function doOne(){
  if [ "$1" == "" ] || [ "$2" != "" ]; then echo "[doOne] ERROR! Invalid arguments '$@' to doOne"; return 1; fi
  echo "[doOne ($1)] $(date) starting in $(pwd)"
  # Configure WL copy
  # Execute WL copy
  echo "[doOne ($1)] do one! (process $1 of $NCOPIES)"
  #for i in $(seq $NTHREADS); do echo "HALLO WORLD $i"; done
  #for i in $(seq $NTHREADS); do source /cvmfs/belle.cern.ch/el7/tools/b2setup; b2analysis-create bmk-04-01-05 release-04-01-05; cd bmk-04-01-05; b2setup; cp /root/bmk-04-01-05/bmk.py .; basf2 bmk.py; done
  curdir=`pwd`
  ln -s $BMKDIR/bmk-04-01-05 bmk-04-01-05
  cd bmk-04-01-05
  #ls
  source /cvmfs/belle.cern.ch/tools/b2setup release-04-01-05
  echo "Executing the following number of threads:"
  echo $NTHREADS
  basf2 bmk.py -n $(( $NEVENTS_THREAD * $NTHREADS )) -p $NTHREADS > $curdir/output
  cd $curdir
  #echo "_________________________________________________OUTPUT START_________________________________________________"
  cat output
  #echo "_________________________________________________OUTPUT END_________________________________________________"
  ln -s $BMKDIR/parse.py parse.py
  ln -s $BMKDIR/parsetwo.py parsetwo.py
  python parse.py $(( $NEVENTS_THREAD * $NTHREADS )) > parsedoutput
  pwd
  #cat parsedoutput
  #b2analysis-create bmk-04-01-05 release-04-01-05
  #cd bmk-04-01-05
  #b2setup 
  #cp /root/bmk-04-01-05/bmk.py .
  #basf2 bmk.py
  #status=0
  status=$?
  echo "[doOne ($1)] $(date) completed (status=$status)"
  # Return 0 if this workload copy was successful, 1 otherwise
  return $status
}

# Optional function validateInputArguments may be defined in each benchmark
# If it exists, it is expected to set NCOPIES, NTHREADS, NEVENTS_THREAD
# (based on previous defaults and on user inputs USER_NCOPIES, USER_NTHREADS, USER_NEVENTS_THREADS)
# Input arguments: none
# Return value: please return 0 if input arguments are valid, 1 otherwise
# The following variables are guaranteed to be defined: NCOPIES, NTHREADS, NEVENTS_THREAD
# (benchmark defaults) and USER_NCOPIES, USER_NTHREADS, USER_NEVENTS_THREADS (user inputs)
function validateInputArguments(){
  if [ "$1" != "" ]; then echo "[validateInputArguments] ERROR! Invalid arguments '$@' to validateInputArguments"; return 1; fi
  echo "[validateInputArguments] validate input arguments"
  # Dummy version: accept user inputs as they are
  if [ "$USER_NCOPIES" != "" ]; then NCOPIES=$USER_NCOPIES; fi
  if [ "$USER_NTHREADS" != "" ]; then NTHREADS=$USER_NTHREADS; fi
  if [ "$USER_NEVENTS_THREAD" != "" ]; then NEVENTS_THREAD=$USER_NEVENTS_THREAD; fi
  # Return 0 if input arguments are valid, 1 otherwise
  return 0
}

# Optional function usage_detailed may be defined in each benchmark
# Input arguments: none
# Return value: none
function usage_detailed(){
  echo "NCOPIES*NTHREADS may be lower or greater than nproc=$(nproc)"
}

# Default values for NCOPIES, NTHREADS, NEVENTS_THREAD must be set in each benchmark
NTHREADS=4
NCOPIES=$(( `nproc` / $NTHREADS )) # (do not use NTHREADS=1, to allow tests that this can be changed)
NEVENTS_THREAD=50

# Source the common benchmark driver
if [ -f $(dirname $0)/bmk-driver.sh ]; then
  . $(dirname $0)/bmk-driver.sh
else
  . $(dirname $0)/../../../common/bmk-driver.sh
fi
