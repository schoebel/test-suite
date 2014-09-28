#!/bin/bash

SETUP
LOAD_start
IMPACT_net_cut_start
IMPACT_destroy
IMPACT_logrotate
IMPACT_net_cut_stop
REPAIR
CHECK
