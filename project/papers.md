# FPGA relevant papers summary
## paper 1:

### A Custom Precision Based Architecture for Accelerating Parallel Tempering MCMC
on FPGAs Without Introducing Sampling Error

Abstract—Markov Chain Monte Carlo (MCMC) is a method
used to draw samples from probability distributions in order
to estimate - otherwise intractable - integrals. When the
distribution is complex, simple MCMC becomes inefﬁcient
and advanced, computationally intensive MCMC methods are
employed to make sampling possible. This work proposes
a novel streaming FPGA architecture to accelerate Parallel
Tempering, a widely adopted MCMC method designed to
sample from multimodal distributions. The proposed archi-
tecture demonstrates how custom precision can be intelligently
employed without introducing sampling errors, in order to save
resources and increase the sampling throughgput. Speedups of
up to two orders of magnitude compared to software and 1.53x-
76.88x compared to a GPGPU implementation are achieved
when performing Bayesian inference for a mixture model.


https://cas.ee.ic.ac.uk/people/ccb98/papers/MingasFCCM12.pdf


## paper 2:

#### Demonstration of FPGA Acceleration of Monte
Carlo Simulation

Abstract. We present results from a stand-alone simulation of electron single Coulomb
scattering as implemented completely on an Field Programmable Gate Array (FPGA)
architecture and compared with an identical simulation on a standard CPU. FPGA architectures
offer unprecedented speed-up capability for Monte Carlo simulations, however with the caveats
of lengthy development cycles and resource limitation, particularly in terms of on-chip memory
and DSP blocks. As a proof of principle of acceleration on an FPGA, we chose a single
scattering process of electrons in water at an energy of 6 MeV. The initial code-base was
implemented in C++ and optimised for CPU processing. To measure the potential performance
gains of FPGAs compared to modern multi-core CPUs we computed 100M histories of a 6
MeV electron interacting in water. Without performing any hardware-specific optimisation,
the results show that the FPGA implementation is over 110 times faster than an optimised
parallel implementation running on 12 CPU-cores, and over 270 times faster than a sequential
single-core CPU implementation. The results on both architectures were statistically equivalent.
The successful implementation and acceleration results are very encouraging for the future
exploitation of more sophisticated Monte Carlo simulation on FPGAs for High Energy Physics
applications.

https://indico.cern.ch/event/1170079/attachments/2484554/4269717/Demonstration_of_FPGA_Acceleration_of_MonteCarlo_Simulation%20(1).pdf


## paper 3: 

### Accelerating Adaptive Parallel Tempering with FPGA-based p-bits

 Abstract:
Special-purpose hardware to solve optimization problems formulated as Ising models has generated great excitement recently. Despite a large diversity in hardware, most solvers employ standard variations of the classical (simulated) annealing (CA) algorithm. Here, we show how powerful replica-based Parallel Tempering (PT) algorithms can significantly outperform CA, using FPGA-based probabilistic computers. Using a massively parallel (graph-colored) architecture, we implement the Adaptive PT (APT) algorithm, generating problem-dependent temperature profiles to equalize replica swap probabilities. We benchmark our p-computer against analytical results from classical Ising theory and use our machine to solve spin-glass instances formulated as hard optimization problems. APT outperforms heuristic choices of temperature profiles used in conventional PT and a replica-based version of CA. Our machine provides 6,000X speedup over optimized CPU, with orders of magnitude further speedup projected for scaled implementations. The developed co-design techniques may be useful for a broad range of Ising machines beyond p-computers.

https://ieeexplore.ieee.org/document/10185207


## paper 4

### Approximate and Stochastic Ising Machines

 Abstract:
The Ising model is useful in searching for (sub)-optimal solutions of combinatorial optimization problems (COPs). CMOS implementations of Ising model-based solvers, commonly referred to as Ising machines, provide reliable and accurate solutions with flexible and dense connectivities. However, they incur a significant hardware overhead. Approximate computing, as a low-power technique, offers a way to reduce hardware complexity, while stochastic computing is efficient in simulating the dynamics of the Ising model. The approximations introduced by these techniques may be beneficial in helping the system escape from local minima. In this article, we discuss the potential of using approximate and stochastic computing to improve the performance of Ising machines.

https://ieeexplore.ieee.org/document/11039732


## paper 5

### Pushing the boundary of quantum advantage in hard combinatorial optimization with probabilistic computers

Abstract

Recent demonstrations on specialized benchmarks have reignited excitement for quantum computers, yet their advantage for real-world problems remains an open question. Here, we show that probabilistic computers, co-designed with hardware to implement Monte Carlo algorithms, provide a scalable classical pathway for solving hard optimization problems. We focus on two algorithms applied to three-dimensional spin glasses: discrete-time simulated quantum annealing and adaptive parallel tempering. We benchmark these methods against a leading quantum annealer. For simulated quantum annealing, increasing replicas improves residual energy scaling, consistent with extreme value theory. Adaptive parallel tempering, supported by non-local isoenergetic cluster moves, scales more favorably and outperforms simulated quantum annealing. Field Programmable Gate Arrays or specialized chips can implement these algorithms in modern hardware, leveraging massive parallelism to accelerate them while improving energy efficiency. Our results establish a rigorous classical baseline for assessing practical quantum advantage and present probabilistic computers as a scalable platform for real-world optimization challenges.

https://www.nature.com/articles/s41467-025-64235-y