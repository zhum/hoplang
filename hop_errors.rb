module Hopsa
  class BadHop < StandardError
  end

  class UnexpectedEOF < StandardError
  end

  class SyntaxError < StandardError
  end

  class VarNotFound < StandardError
  end
end
