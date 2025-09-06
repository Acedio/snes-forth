BEGIN {
  FS="," ; OFS=","
} 
{
  for (i = 1; i <= NF; i++) {
    $i = palette + or(and($i * 2, 0xF), and($i, 0xF8) * 4)
  }
  printf(".WORD ");
  print;
}
