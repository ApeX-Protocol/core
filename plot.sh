output=$1

pnl=$(echo "$(awk -F', ' '{s+=$6}; END {print s}' $1) / 10^18" | bc -l)
beta=$(echo $1 | awk -F'[^0-9]+' '{ print $2 }')

gnuplot <<- EOF
  set terminal png size 2400,1800
  set output '$(basename ${output} .csv).png'
  set key outside
  set datafile separator ","
  set title font ",22"
  set title "Beta: $beta **** PnL: $pnl"

  plot '${output}' using 0:2 with lines title "Oracle Price", '' using 0:3 with lines title "Pool Price",\
       '' using 0:3:(10-\$1):(abs(\$1*2)) w points pt variable ps variable lc rgb 'blue' title "",\
       '' using 0:3:(10-\$4):(abs(\$4*2)) w points pt variable ps variable lc rgb 'red' title "",\
       '' using (\$4 == 0 ? NaN : \$0):3:(\$3 > \$5 ? \$5 : \$3):(\$3 > \$5 ? \$3 : \$5) with yerrorbars title ""
EOF
