#!/bin/bash
#
# Copyright 2014 Thomas Schoebel-Theuer
# Programmed in my spare time on my private notebook.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

# Standard predicates on "marsadm view all"

pred_all_flushed=${pred_all_flushed:-(( \$(grep -c ' [-dD]c[-aA][-sS][-fF][-rR] ') == 0 ))}
pred_all_applied=${pred_all_applied:-(( \$(grep -o ' [-dD][-cC][-aA][-sS][-fF][-rR] ' | grep -c '\([-c]...\|[-s]..\|[-f].\|[-r]\) $' ) == 0 ))}
pred_all_=${pred_all_:-}

# Standard predicates on "marsadm view $lv"
# A specific lv _must_ be given!

pred_lv_applied=${pred_lv_applied:-(( \$(grep -c ' [-dD]C[-aA]SFR ') > 0 ))}
pred_lv_uptodate=${pred_lv_uptodate:-grep UpToDate} # Warning! This bears uncertainity! Use pred_lv_applied instead!
pred_lv_not_applied=${pred_lv_not_applied:-(( \$(grep -c ' [-dD][-cC][-aA][-sS][-fF][r] ') > 0 ))}
pred_lv_=${pred_lv_:-}

# Standard predicates on "marsadm view-is-$something $lv"

pred_is_0=${pred_is_0:-grep '^0$'}
pred_is_1=${pred_is_1:-grep '^1$'}
pred_is_greater_0=${pred_is_greater_0:-(( \$(grep '^[0-9]\\\+\$') > 0 ))}
pred_is_greater_4096=${pred_is_greater_4096:-(( \$(grep '^[0-9]\\\+\$') > 4096 ))}
