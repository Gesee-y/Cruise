# Cruise Assets

This module is the one responsible for loading assets for Cruise.
Cruise asset pipeline is basically this:

- We load some assets from files
- We process them (compress, resize, mipmap if requested)
- We can create an optimized version of the asset that we can actually use without using all  the bandwith, even though the original asset my be big.