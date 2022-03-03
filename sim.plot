set terminal png size 1200,900
set output 'sim.png'

plot 'sim.csv' using 0:1 with lines, '' using 0:2 with lines
