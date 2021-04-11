
import numpy as np
import os
try:
    import astropy.units as u
    wsw_cooling = {
                   'beta': [2.12,1.,0.56,3.21,-0.2,-3.,-0.22,-3.,0.33,0.5],
                   'T_k': [
                           90     * u.K,
                           141    * u.K,
                           313    * u.K,
                           6102   * u.K,
                           1e5    * u.K,
                           2.88e5 * u.K,
                           4.73e5 * u.K,
                           2.11e6 * u.K,
                           3.98e6 * u.K,
                           2.00e7 * u.K
                          ],
                   'lambda': [
                              3.703109927416290e16 * u.Unit('erg g-2 s-1 cm3'),
                              9.455658188464892e18 * u.Unit('erg g-2 s-1 cm3'),
                              1.185035244783337e20 * u.Unit('erg g-2 s-1 cm3'),
                              1.102120336e10       * u.Unit('erg g-2 s-1 cm3'),
                              1.236602671e27       * u.Unit('erg g-2 s-1 cm3'),
                              2.390722374e42       * u.Unit('erg g-2 s-1 cm3'),
                              4.003272698e26       * u.Unit('erg g-2 s-1 cm3'),
                              1.527286104e44       * u.Unit('erg g-2 s-1 cm3'),
                              1.608087849e22       * u.Unit('erg g-2 s-1 cm3'),
                              9.228575532e20       * u.Unit('erg g-2 s-1 cm3')
                             ]
                  }

    gressel_cooling = {
                   'beta': [2.12,1.,0.56,3.21,-0.2,-3.,-0.22,-3.,0.33,0.5],
                   'T_k': [
                           10     * u.K,
                           141    * u.K,
                           313    * u.K,
                           6102   * u.K,
                           1e5    * u.K,
                           2.88e5 * u.K,
                           4.73e5 * u.K,
                           2.11e6 * u.K,
                           3.98e6 * u.K,
                           2.00e7 * u.K
                          ],
                   'lambda': [
                              3.42e16 * u.Unit('erg g-2 s-1 cm3'),
                              9.10e18 * u.Unit('erg g-2 s-1 cm3'),
                              1.11e20 * u.Unit('erg g-2 s-1 cm3'),
                              1.064e10 * u.Unit('erg g-2 s-1 cm3'),
                              1.147e27 * u.Unit('erg g-2 s-1 cm3'),
                              2.29e42 * u.Unit('erg g-2 s-1 cm3'),
                              3.80e26 * u.Unit('erg g-2 s-1 cm3'),
                              1.445e44 * u.Unit('erg g-2 s-1 cm3'),
                              1.513e22 * u.Unit('erg g-2 s-1 cm3'),
                              8.706e20 * u.Unit('erg g-2 s-1 cm3')
                             ]
                  }
except ImportError:
    wsw_cooling = {
                   'beta': [2.12,1.,0.56,3.21,-0.2,-3.,-0.22,-3.,0.33,0.5],
                   'T_k': [
                           90     ,
                           141    ,
                           313    ,
                           6102   ,
                           1e5    ,
                           2.88e5 ,
                           4.73e5 ,
                           2.11e6 ,
                           3.98e6 ,
                           2.00e7
                          ],
                   'lambda': [
                              3.703109927416290e16,
                              9.455658188464892e18,
                              1.185035244783337e20,
                              1.102120336e10      ,
                              1.236602671e27      ,
                              2.390722374e42      ,
                              4.003272698e26      ,
                              1.527286104e44      ,
                              1.608087849e22      ,
                              9.228575532e20
                             ]
                  }

    gressel_cooling = {
                   'beta': [2.12,1.,0.56,3.21,-0.2,-3.,-0.22,-3.,0.33,0.5],
                   'T_k': [
                           10     ,
                           141    ,
                           313    ,
                           6102   ,
                           1e5    ,
                           2.88e5 ,
                           4.73e5 ,
                           2.11e6 ,
                           3.98e6 ,
                           2.00e7
                          ],
                   'lambda': [
                              3.42e16 ,
                              9.10e18 ,
                              1.11e20 ,
                              1.064e10,
                              1.147e27,
                              2.29e42 ,
                              3.80e26 ,
                              1.445e44,
                              1.513e22,
                              8.706e20
                             ]
                  }

