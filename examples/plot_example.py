import numpy as np 
import matplotlib.pyplot as plt
import argparse
import os
import sys
sys.path.append("examples")
import utils

savefigs = True

# Parse arguments.
parser = argparse.ArgumentParser("Create violin plot of inverse evidences" +
    "from many realisations")
parser.add_argument('filename_realisations', metavar='filename_realisations', 
                    type=str, 
                    help='Name of file containing realisations')
parser.add_argument('filename_analytic', metavar='filename_analytic', 
                    type=str, 
                    help='Name of file containing analytic inverse variance')
args = parser.parse_args()

# Load data.
evidence_inv_summary = np.loadtxt(args.filename_realisations)
evidence_inv_realisations = evidence_inv_summary[:,0]
evidence_inv_var_realisations = evidence_inv_summary[:,1]
evidence_inv_var_var_realisations = evidence_inv_summary[:,2]

evidence_inv_analytic = np.loadtxt(args.filename_analytic)

# Plot inverse evidence.
plt.rcParams.update({'font.size': 20})    
ax = utils.plot_realisations(mc_estimates=evidence_inv_realisations,  
                             std_estimated=np.sqrt(np.mean(evidence_inv_var_realisations)),
                             analytic_val=evidence_inv_analytic,
                             analytic_text=r'Truth')
plt.ticklabel_format(style='sci', axis='y', scilimits=(0,0))                             
ax.set_ylabel(r'Inverse evidence ($\rho$)')
# ax.set_ylim([0.0077, 0.0087])

filename_base = os.path.basename(args.filename_realisations)
filename_base_noext = os.path.splitext(filename_base)[0]
if savefigs:
    plt.savefig('./plots/' + filename_base_noext + '_evidence_inv.pdf',
                bbox_inches='tight')      
        
# Plot variance of inverse evidence.        
ax = utils.plot_realisations(mc_estimates=evidence_inv_var_realisations, 
                             std_estimated=np.sqrt(np.mean(evidence_inv_var_var_realisations)))
plt.ticklabel_format(style='sci', axis='y', scilimits=(0,0))        
ax.set_ylabel(r'Inverse evidence variance ($\sigma^2$)')        
# ax.set_ylim([-0.5E-8, 1.5E-8])
    
if savefigs:
    plt.savefig('./plots/' + filename_base_noext + '_evidence_inv_var.pdf',
                bbox_inches='tight')                  
        
plt.show(block=False)

input("\nPress Enter to continue...")
