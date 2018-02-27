import numpy as np
cimport numpy as np
import chains as ch
from libc.math cimport exp

class Evidence:
    """Compute inverse evidence values from chains, using posterior model.  
    
    Multiple chains can be added in sequence (to avoid having to store very long chains).    
    """
        
    def __init__(self, long nchains, model not None):
        """Construct evidence class for computing inverse evidence values from set number of chains and initialised posterior model.        

        Args:
            long nchains: Number of chains that will be used in the compuation.
            model: An instance of a posterior model class that has been fitted.
        
        Raises:
            ValueError: Raised if the number of chains is not positive.
            ValueError: Raised if the number of dimensions is not positive.            
            ValueError: Raised if model not fitted.
        """
        if nchains < 1:
            raise ValueError("nchains must be greater than 0.")

        if model.ndim < 1:
            raise ValueError("ndim must be greater than 0.")
                
        if not model.is_fitted():
            raise ValueError("Model not fitted.")

        self.running_sum = np.zeros(nchains)
        self.nsamples_per_chain = np.zeros((nchains),dtype=long)

        self.nchains = nchains
        self.ndim = model.ndim
        self.evidence_inv = 0.0
        self.evidence_inv_var = 0.0
        self.evidence_inv_var_var = 0.0

        self.mean_shift_set = False
        self.mean_shift = 0.0
        
        self.chains_added = False
        
        self.model = model

    def set_mean_shift(self, double mean_shift_in):        
        """Set the multiplicative shift of log_e posterior values to aid numerical stability (usually the geometric mean).

        Args:
            double mean_shift_in: Multiplicative shift.

        Raises:
            ValueError: If mean_shift_in is NaN .
        """
        if ~np.isfinite(mean_shift_in):
            raise ValueError("Mean shift must be a number")

        self.mean_shift = mean_shift_in
        self.mean_shift_set = True
        return

    def process_run(self):        
        """Use the running totals of running_sum and nsamples_per_chain
        to calculate an estimate of the inverse evidence, its variance,
        and the variance of the variance.

        This method is ran each time chains are added to update the inverse variance estimates from the running totals.

        Args:
            None

        Raises:
            None
        """

        cdef np.ndarray[double, ndim=1, mode="c"] running_sum = self.running_sum
        cdef np.ndarray[long, ndim=1, mode="c"] nsamples_per_chain = self.nsamples_per_chain

        cdef long i_chains, nsamples=0, nchains = self.nchains
        cdef double evidence_inv=0.0, evidence_inv_var=0.0, kur=0.0, dummy, n_eff=0

        for i_chains in range(nchains):
            evidence_inv             += running_sum[i_chains]
            nsamples += nsamples_per_chain[i_chains]
        evidence_inv /= nsamples

        for i_chains in range(nchains):
            dummy  = running_sum[i_chains]/nsamples_per_chain[i_chains]
            dummy -= evidence_inv
            n_eff += nsamples_per_chain[i_chains]*nsamples_per_chain[i_chains]
            evidence_inv_var    += nsamples_per_chain[i_chains]*dummy*dummy
            kur     += nsamples_per_chain[i_chains]*dummy*dummy*dummy*dummy

        n_eff = <double>nsamples*<double>nsamples/n_eff
        evidence_inv_var   /= nsamples
        kur    /= nsamples
        kur    /= evidence_inv_var*evidence_inv_var

        self.evidence_inv = evidence_inv*exp(-self.mean_shift)
        self.evidence_inv_var = evidence_inv_var*exp(-2*self.mean_shift)/(n_eff)
        self.evidence_inv_var_var  = evidence_inv_var**2*exp(-4*self.mean_shift)/(n_eff*n_eff*n_eff)
        self.evidence_inv_var_var *= ((kur - 1) + 2./(n_eff-1))
        return

    def add_chains(self, chains not None):        
        """Add new chains and calculate an estimate of the inverse evidence, its
        variance, and the variance of the variance.  
        
        Calculations are performed by using running averages of the totals for
        each chain. Consequently, the method can be called many times with new
        samples for each chain so that the evidence estimate will improve.  The
        rationale is that not all samples need to be stored in memory for
        high-dimensional problems.  Note that the same number of chains needs to
        be considered for each call.

        Args:
            chains: An instance of the chains class containing the chains
                to be used in the calculation.            

        Raises:
            ValueError: If the input number of chains to not match the number
                of chains already set up.

        Returns:
            None
        """

        if chains.nchains != self.nchains:
            raise ValueError("nchains do not match")

        if chains.ndim != self.ndim:
            raise ValueError("Chains ndim inconsistent")

        cdef np.ndarray[double, ndim=2, mode="c"] X = chains.samples
        cdef np.ndarray[double, ndim=1, mode="c"] Y = chains.ln_posterior
        cdef np.ndarray[double, ndim=1, mode="c"] running_sum = self.running_sum
        cdef np.ndarray[long,   ndim=1, mode="c"] nsamples_per_chain = self.nsamples_per_chain

        cdef long i_chains, i_samples, nchains = self.nchains
        cdef double mean_shift

        if ~self.mean_shift_set:
            self.set_mean_shift(np.mean(Y))
        mean_shift = self.mean_shift

        for i_chains in range(nchains):
            i_samples_start = chains.start_indices[i_chains]
            i_samples_end = chains.start_indices[i_chains+1]
            for i_samples in range(i_samples_start, i_samples_end):
                running_sum[i_chains] += exp( self.model.predict(X[i_samples,:]) \
                    - Y[i_samples] + mean_shift )
                nsamples_per_chain[i_chains] += 1

        self.process_run()
        
        self.chains_added = True

        return

    def compute_evidence(self):
        """Compute evidence from the inverse evidence.
        
        Args: 
            None.

        Returns: (evidence, evidence_std)
            evidence: Estimate of evidence.
            evidence_std: Estimate of standard deviation of evidence.
        """
        
        common_factor = 1.0 + self.evidence_inv_var/(self.evidence_inv**2)
        
        evidence = common_factor / self.evidence_inv        
        
        evidence_std = np.sqrt(common_factor) / self.evidence_inv
        
        return (evidence, evidence_std)
        
    def compute_ln_evidence(self):
        """Compute log_e of evidence from the inverse evidence.
        
        Args: 
            None.

        Returns: (ln_evidence, ln_evidence_std)
            ln_evidence: Estimate of log_e of evidence.
            ln_evidence_std: Estimate of log_e of standard deviation of evidence.
        """
        
        common_factor = 1.0 + self.evidence_inv_var/(self.evidence_inv**2)
        
        ln_evidence = np.log(common_factor) - np.log(self.evidence_inv)
        
        ln_evidence_std = 0.5*np.log(common_factor) - np.log(self.evidence_inv)
        
        return (ln_evidence, ln_evidence_std)        
        

def compute_bayes_factor(ev1, ev2):
    """Compute Bayes factor of two models.
    
    Args:
        ev1: Evidence object of model 1 with chains added.
        ev2: Evidence object of model 2 with chains added.
    
    Returns: (bf12, bf12_std)
        bf12: Estimate of the Bayes factor Z_1 / Z_2.
        bf12_std: Estimate of the standard deviation of the Bayes factor
            Z_1 / Z_2.
    
    Raises:
        ValueError: Raised if model 1 does not have chains added. 
        ValueError: Raised if model 2 does not have chains added. 
    """
    
    if not ev1.chains_added:
        raise ValueError("Evidence for model 1 does not have chains added")
    if not ev2.chains_added:
        raise ValueError("Evidence for model 2 does not have chains added")
        
    common_factor = 1.0 + ev1.evidence_inv_var/(ev1.evidence_inv**2)

    bf12 = ev2.evidence_inv / ev1.evidence_inv * common_factor
    
    bf12_std = np.sqrt( ev1.evidence_inv**2 * ev2.evidence_inv_var \
                        + ev2.evidence_inv**2 * ev1.evidence_inv_var ) \
                      / (ev1.evidence_inv**2)
    
    return (bf12, bf12_std)

def compute_ln_bayes_factor(ev1, ev2):
    """Compute log_e of Bayes factor of two models.
    
    Args:
        ev1: Evidence object of model 1 with chains added.
        ev2: Evidence object of model 2 with chains added.
    
    Returns: (ln_bf12, ln_bf12_std)
        ln_bf12: Estimate of log_e of the Bayes factor Z_1 / Z_2.
        ln_bf12_std: Estimate of log_e of the standard deviation of the Bayes 
            factor Z_1 / Z_2.
    
    Raises:
        ValueError: Raised if model 1 does not have chains added. 
        ValueError: Raised if model 2 does not have chains added. 
    """
    
    if not ev1.chains_added:
        raise ValueError("Evidence for model 1 does not have chains added")
    if not ev2.chains_added:
        raise ValueError("Evidence for model 2 does not have chains added")
        
    common_factor = 1.0 + ev1.evidence_inv_var/(ev1.evidence_inv**2)

    ln_bf12 = np.log(ev2.evidence_inv) - np.log(ev1.evidence_inv) \
        + np.log(common_factor)
        
    factor = ev1.evidence_inv**2 * ev2.evidence_inv_var \
             + ev2.evidence_inv**2 * ev1.evidence_inv_var
             
    ln_bf12_std = 0.5*np.log(factor) - 2.0 * np.log(ev1.evidence_inv)
    
    return (ln_bf12, ln_bf12_std)
    