[![Checking Status](http://webmail.parallel.ru:8080/job/HopLang/badge/icon)](http://webmail.parallel.ru:8080/job/HopLang/) 

# HOPLANG

Revolutional data processing language. World domination toolset component...

## Notes

  - Syntax is described in wiki
  - Hopstance - class for stream processing
  - hop method = do it!
  - createNewRetLineNum method = get current text and position, then process it,
   create new Hopstance, change text (optionally, if optimizations were made),
   and return created Hopstance and new position in text
  - do_yield method = do yield :)

## Required modules (rubygems)

  - cassandra (opt) - used to interact with Cassandra DB
  - mongodb, bson_ext (opt) - used to interact with NongoDB
  - citrus - used for expression grammar
  - 

## Installing

  - copy repository
  - run gem install hopcsv*gem
  - run bundle install
  - All DONE! You can run hpl, or specify "require 'hoplang'" in your programs

## Testing

  rake - run all rspec tests

  To tun selected tests use something like this:

```bash
  hpl tests/var_test.hpl
  bin/hpl tests/top_test.hpl
```
