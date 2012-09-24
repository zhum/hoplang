Hopsa::CITRUS_NODESET_GRAMAR=<<-'END'
# citrus grammar for nodesets
grammar NodeSetGram
	# main target
	rule nodeset
		(cat (',' cat)*)	{
		  es = captures[:cat].map {|cap| cap.value}
		  Hopsa::ChoiceSetNode.new es
		}
	end
	rule cat
		(catpart+) {
		  es = captures[:catpart].map {|cap| cap.value}
		  Hopsa::CatSetNode.new es
    }
	end
	rule catpart
		(bracketed | fixed)
	end
	rule bracketed
		('[' brackpart (',' brackpart)* ']') {
		  es = captures[:brackpart].map {|cap| cap.value}
		  Hopsa::BracketedSetNode.new es
		}
	end
	rule brackpart
		(digits ('-' digits)?) {
		  strs = captures[:digits].map {|cap| cap.value}
		  if strs.length == 2
		    Hopsa::RangeSetNode.new strs[0], strs[1]
		  else
		    Hopsa::FixedSetNode.new strs[0]
	    end
		}
	end
  rule fixed
		(data empty) { Hopsa::FixedSetNode.new data.value	}
	end
	rule digits
		([0-9]+) { to_s }
	end
	rule data
		([-_a-zA-Z0-9]+) { to_s }
	end
	rule empty
	end
end
END
