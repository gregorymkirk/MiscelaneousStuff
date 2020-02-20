!#/bin/bash
# Let's chw up some CPU cycles for no good reason
# useful for testing autoscaling groups in AWS, and anwhere else you need to know what happens when the CPU get full

stress --cpu 4000

