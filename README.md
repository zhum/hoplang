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

## Notes about coding

Hopstance - base hoplang block for stream processing. There
are several Hopstances - each, groupby, sort, etc. Every hopstance
type is derived from Hopstance class.

Hopstance MUST have methods:
 - self.createNewRetLineNum(parent,text,pos) - receives parent
 hopstance, current program text (strings array) and current text
 position. It must return pair - new hopstance instance and new
 text position.
 - hop - start working!
 - do_yield(hash) - process 'yield' statement. It must write
 hash into output stream.
 - readSource -  read next source stream line and write it
 into @source_var
