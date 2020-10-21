HEPWL_BMKEXE=belle2-gen-sim-reco-bmk.sh
#HEPWL_BMKOPTS="-e 4 -c 5" # -c replaces -n as of v0.7
HEPWL_BMKOPTS="-e 20 -c 2" # -c replaces -n as of v0.7
HEPWL_BMKDIR=belle2-gen-sim-reco
HEPWL_BMKDESCRIPTION="belle2-gen-sim-reco-bmk"
HEPWL_DOCKERIMAGENAME=belle2-gen-sim-reco-bmk
HEPWL_DOCKERIMAGETAG=v0.15 # versions >= v0.6 use common bmk driver, >= v0.9 use separate GEN/SIM scores
HEPWL_CVMFSREPOS=belle.cern.ch
