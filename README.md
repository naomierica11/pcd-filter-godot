git remote add origin https://github.com/<user>/<repo>.git
git fetch origin
git branch -M main
git rebase origin/main   # atau: git merge origin/main
git push -u origin main
