# HOMEMADE RESTIC UTIL
# PART 2: CHECK IT UP

# ADD TO CRON:
#  xyzzy
# RUN ON A SINGLE MACHIE

source .env

restic check --read-data-subset=10%