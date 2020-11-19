#!/bin/bash
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
  ln -s $BMKDIR/parseResults.py parseResults.py
  ./parseResults.py $NEVENTS_THREAD
  #local score=1 # hardcoded (dummy)
  #local msg="OK"
  #local app="\"UNKNOWN\""
  #local app="\"belle2-gen-sim-reco-bmk\""
  #local json=belle2-gen-sim-reco_summary.json
  #cd proc_1
  #python parsetwo.py $NCOPIES > score
  #cat score
  #cd ..
  #cat proc_1/score
  #for i in $(seq $NCOPIES); do echo $i; ls proc_$i; cat proc_$i/parsedoutput; done
  #python parsetwo.py $NCOPIES > score
  #local score=`cat proc_1/score`
  #echo -e "{ \"copies\" : $NCOPIES , \"threads_per_copy\" : $NTHREADS , \"events_per_thread\" : $NEVENTS_THREAD , \"throughput_score\" : $score , \"log\": \"$msg\", \"app\" : ${app} }" > ${json} && cat ${json}
  # Return 0 if parsing was successful, 1 otherwise
  return 0
}
