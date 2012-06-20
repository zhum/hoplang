[![Checking Status](http://webmail.parallel.ru:8080/job/HopLang/badge/icon)](http://webmail.parallel.ru:8080/job/HopLang/)

# HOPLANG

Revolutional data processing language. World domination toolset component...

## Notes

  - Syntax will be described later in wiki
  - Hopstance - class for stream processing
  - hop method = do it!
  - createNewRetLineNum method = get current text and position, then process it,
   create new Hopstance, change text (optionally, if optimizations were made),
   and return created Hopstance and new position in text
  - do_yield method = do yield :)

## Required modules (rubygems)

  - cassandra - used to interact with Cassandra DB
  - citrus - used for expression grammar

## Testing

hoprun.rb = hoplang executor. e.g.

```bash
 hoprun.rb vartest.hpl
```
