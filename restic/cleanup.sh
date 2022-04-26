# HOMEMADE RESTIC UTIL
# PART 3: CLEAN IT UP

# ADD TO CRON:
#  xyzzy
# RUN ON A SINGLE MACHIE

source .env

restic prune --forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 75