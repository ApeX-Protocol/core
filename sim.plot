set terminal png size 2400,1800
set output 'sim.png'
set key autotitle columnheader
set key outside
set datafile separator ","

plot 'sim.csv' using 0:1 with lines, '' using 0:2 with lines
