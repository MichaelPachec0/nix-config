#! /usr/bin/env bash
# testparams ()
# {
#   
#   echo "inside testparams \$1 should be equal to 1 and \$2 should be equal to outer \$1  \$1 ${1}  \$2 ${2}"
# }
# echo "outside of testparams,\$2 should be emtpy \$1 ${1} \$2 ${2}"
# testparams  1 "$1"
## Command that generates the output
CMD=$(swaymsg -t get_outputs)
# This spits all the swaymsg stuff, then goes line by line
echo "$CMD" | while IFS= read -r line; do
    # if line matches name (only happens on ouput name)
    if [[ $line =~ \"name\"  ]]; then
        # only grab the most important part of the line, the output name.
        display=$(echo "$line" | tr -d " " | cut -d ":" -f 2 | sed 's/\"\(.*\)\",/\1/')
        echo "$display"
    fi
done
