from PyNEC import *
import numpy as np
import math

def to_radians(x):
  return x * math.pi / 180.0

def from_db(x):
  return 10.0**(x/10)

def n_seg(freq, length):
  wavelength = 3e8/(1e6*freq)
  return (2 * (int(math.ceil(77*length/wavelength))/2)) + 1
  
def quad_helix(freq, base, length, angle, phi_start, phi_stop):
    #creation of a nec context
    context=nec_context()

    #get the associated geometry
    geo = context.get_geometry()
    
    wavelength = 3.0e8/(1e6*freq)
    wire_r = (0.0088 * wavelength)/2;
    wire_r = wire_r / 2
    
    big_height = 0.26*wavelength;
    big_r = (0.173*wavelength)/2;
    big_leg_size = 0.560*wavelength;

    small_height =  0.238*wavelength;
    small_r = (0.156*wavelength/2);
    small_leg_size = 0.508*wavelength;

    conductivity = 1.45e7 # Copper
    ground_conductivity = 0.002
    ground_dielectric = 10

    big_z = 0.2
    diff_z = (big_height - small_height)/2
    
    print "Wire Diameter %s" % (wire_r * 2)
    print "Height Difference %s" % diff_z
    
    helix_turns = 0.5
    
    # Big helix
    big_helix_twist_length = big_height / helix_turns
    geo.wire(1, n_seg(freq, big_r), 0, 0, big_z, 0,  big_r, big_z, wire_r, 1.0, 1.0)
    geo.wire(1, n_seg(freq, big_r), 0, 0, big_z, 0, -big_r, big_z, wire_r, 1.0, 1.0)
    geo.helix(big_helix_twist_length, big_height, 0,  big_r, 0,  big_r, wire_r, n_seg(freq,big_height), 1)
    geo.helix(big_helix_twist_length, big_height, 0, -big_r, 0, -big_r, wire_r, n_seg(freq,big_height), 1)
    geo.wire(2, n_seg(freq, big_r), 0, 0, big_z + big_height, 0,  big_r, big_z + big_height, wire_r, 1.0, 1.0)
    geo.wire(2, n_seg(freq, big_r), 0, 0, big_z + big_height, 0, -big_r, big_z + big_height, wire_r, 1.0, 1.0)
    
    # Small helix
    small_helix_twist_length = small_height / helix_turns
    small_z = big_z + diff_z
    
    geo.wire(3, n_seg(freq, small_r), 0, 0, small_z,  small_r, 0, small_z, wire_r, 1.0, 1.0)
    geo.wire(3, n_seg(freq, small_r), 0, 0, small_z, -small_r, 0, small_z, wire_r, 1.0, 1.0)
    geo.helix(small_helix_twist_length, small_height,  small_r, 0,  small_r, 0, wire_r, n_seg(freq,small_height), 3)
    geo.helix(small_helix_twist_length, small_height, -small_r, 0, -small_r, 0, wire_r, n_seg(freq,small_height), 3)
    
    geo.wire(4, n_seg(freq, small_r), 0, 0, small_z + small_height,  small_r, 0, small_z + small_height, wire_r, 1.0, 1.0)
    geo.wire(4, n_seg(freq, small_r), 0, 0, small_z + small_height, -small_r, 0, small_z + small_height, wire_r, 1.0, 1.0)

    # Join big to small at the top
    geo.wire(5, 3, 0, 0, small_z + small_height, 0,  0, big_z + big_height, 0.001, 1.0, 1.0)
   
    
    context.geometry_complete(1)
    #context.gn_card(0, 4, ground_dielectric,ground_conductivity,0.05,0.001,0,0)
    context.ld_card(5, 0, 0, 0, conductivity, 0.0, 0.0)
    
    # Feed the two loops out of phase (at the top)
    context.ex_card(0, 5, 2, 0, 0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0)
    
    context.fr_card(0, 1, freq, 0)

    n_theta = 90
    n_phi = 10
    theta0 = 0.0
    delta_theta = (360.0/n_theta)
    delta_phi = ((phi_stop - phi_start)/n_phi)

    #add a "rp" card to specify radiation pattern sampling parameters and to cause program execution
    context.rp_card(0, n_theta, n_phi, 1, 5, 0, 1, theta0, phi_start, delta_theta, delta_phi, 1.0, 0.0)

    ip = context.get_input_parameters(0)
    z = ip.get_impedance()
    print z
    #get the radiation_pattern
    rp = context.get_radiation_pattern(0)

    # Gains are in decibels
    gains_db = rp.get_gain()
    #gains = 10.0**(gains_db / 10.0)
    thetas = rp.get_theta_angles() * 3.1415 / 180.0
    phis = rp.get_phi_angles() * 3.1415 / 180.0
    return z, gains_db, thetas, phis

# Plot stuff
import matplotlib.pyplot as plt
from antenna_util import reflection_coefficient

l_best = 0.01
r_best = -9999.9
z0 = 50.0
droop = to_radians(40.0)

#for l in np.linspace(0.03, 0.19, 70):
  #z, gains_db, thetas, phis = quad_helix(freq=1545.42, base=0.1, length=l, angle=droop, phi_start=60, phi_stop=90)
  #gmean = np.mean(np.mean(from_db(gains_db)))
  #gmax = np.max(np.max(from_db(gains_db)))
  #gmin = np.min(np.min(from_db(gains_db)))
  #r = (gmean) * (1.0 - reflection_coefficient(z, z0)) / (1.5 + gmax - gmin)
  #if (r > r_best):
    #r_best = r
    #l_best = l

#print r_best
#print l_best

z, gains_db, thetas, phis = quad_helix(freq=1545.42, base=0.1, length=l_best, angle=droop,  phi_start=5, phi_stop=90)

print z
print reflection_coefficient(z,50)

ax = plt.subplot(111, polar=True)
for j in range(0,10):
  ax.plot(thetas, gains_db[:,j] + 20, linewidth=3, label=("%s" % (phis[j]*180.0/3.1415)))
ax.grid(True)

ax.set_title("Gain at an elevation of 45 degrees", va='bottom')
plt.savefig('RadiationPattern.png')
plt.legend()
plt.show()


#import matplotlib.pyplot as plt
#from mpl_toolkits.mplot3d import Axes3D

#fig = plt.figure()
#ax = fig.add_subplot(111, projection='3d')

#u = np.linspace(0, 2 * np.pi, 100)
#v = np.linspace(0, np.pi, 100)

#x = 10 * np.outer(np.cos(u), np.sin(v))
#y = 10 * np.outer(np.sin(u), np.sin(v))
#z = 10 * np.outer(np.ones(np.size(u)), np.cos(v))
#ax.plot_surface(x, y, z,  rstride=4, cstride=4, color='b')

#plt.show()



#from mpl_toolkits.mplot3d import Axes3D
#import matplotlib
#import numpy as np
#from matplotlib import cm
#from matplotlib import pyplot as plt 

#fig = plt.figure()
#ax = Axes3D(fig)

#R,P = np.meshgrid(thetas,phis) 
## transform them to cartesian system
#X,Y = R*np.cos(P),R*np.sin(P)

#Z = ((R**2 - 1)**2)
#ax.plot_surface(X, Y, Z, rstride=1, cstride=1, cmap=cm.jet)
#ax.set_zlim3d(0, 1)
#ax.set_xlabel(r'$\phi_\mathrm{real}$')
#ax.set_ylabel(r'$\phi_\mathrm{im}$')
#ax.set_zlabel(r'$V(\phi)$')
#ax.set_xticks([])
#plt.show() 
