## How to update the Crail website. 

Please make necessary changes in the master branch. You can test 
the master branch by 
 1. Changing the 'base` in the site/_config.yml from base: 
    'http://crail.incubator.apache.org' to 
    'http://127.0.0.1:4000'
 2. Run the script "test-locally.sh" to test your setup locally. 

Once you are satisfied with your changes, please change the 
site/_config.yml back, and commit your changes to the master 
branch. 

Once you are done pushing all changes to the master branch, run 
"publish.sh" script. This script will build the new website and 
commit the newly generated pages to the "asf-site" branch. If all 
goes well, you just need to push the new commit to the branch by 
calling "git push origin asf-site". 

After this, you switch back to the "master" branch. 

- The master contains the source in 'master/site'.
- The build site is checked into the 'asf-site/content'. 

https://issues.apache.org/jira/browse/CRAIL-1

** 
For older bundle exec jekyll installations (2.4) you might not have 
"clean" command. Then just delete site/_site directory instead of 
calling "bundle exec jekyll clean" in the publish script. And let
run rest of the script. 
