rosie --rpl 'alias b = {[ \t]* [\n]}; alias eoc = find:"*/"; alias c = {[ \t]* "/*" eoc [^\n]* "\n"}; line = find:{>"\n"}; lines = {c / b / line "\n"}+' match -o subs --wholefile lines $@ | wc -l

