set terminal png size 2400,1800
set output 'sim.png'
set key autotitle columnheader
set key outside
set datafile separator ","
set style line 1 lc rgb 'black' pt 9 # triangle

plot 'temp.csv' using 0:2 with lines, '' using 0:3 with lines,\
     '' using 0:3:(10+$1):(abs($1*2)) w points pt variable ps variable lc rgb 'blue',\
     '' using 0:3:(10+$4):(abs($4*2)) w points pt variable ps variable lc rgb 'red'
