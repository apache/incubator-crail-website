PYTHON=python2.7

# targets that aren't filenames
.PHONY: all clean deploy

all: _site/index.html

BUILDARGS :=
_site/index.html _site/wacas14/index.html:
	bundle exec jekyll build $(BUILDARGS)

#_includes/pubs.html: bib/pubs.bib bib/publications.tmpl
#	mkdir -p _includes
#	$(PYTHON) bibble/bibble.py $+ > $@

_site/index.html: $(wildcard *.html) _config.yml _layouts/default.html

clean:
	$(RM) -r _site 

HOST := https://crail.incubator.apache.org
PATHSVR := www/
deploy: clean all
	rsync --compress --recursive --checksum --itemize-changes --delete -e ssh _site/ $(HOST):$(PATHSVR)
