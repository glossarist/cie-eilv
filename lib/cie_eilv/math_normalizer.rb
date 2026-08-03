# frozen_string_literal: true

module CieEilv
  # Normalizes AsciiMath notation in concept YAML files.
  #
  # Fixes three style issues inherited from iev-data:
  #
  # 1. Asciidoc subscript/superscript immediately after a stem block:
  #      stem:[L]~e~          → stem:[L_e]
  #      stem:[E]^mc^2        → stem:[E^mc^2]  (preserved; ^X^ folds to ^X)
  #    The Asciidoc ~X~ / ^X^ was rendering correctly but separated the
  #    math notation across two syntax systems. AsciiMath has its own
  #    _X / ^X inside the stem block, which is the canonical form.
  #
  # 2. Unicode Greek letters adjacent to or inside stem blocks:
  #      Δstem:[t]            → stem:[delta t]
  #      stem:[λ + α]         → stem:[lambda + alpha]
  #    AsciiMath expects Greek names (delta, lambda, alpha, ...), not
  #    Unicode characters. Mixed rendering produced inconsistent output.
  #
  # 3. Consecutive stem blocks joined by Asciidoc subscripts (multi-index):
  #      stem:[L]~e,~stem:[t] → stem:[L_(e,t)]
  #
  # Idempotent: re-running on already-normalized text is a no-op.
  # Works on any concept file regardless of edition (cie-2011, cie-2020,
  # iev-data) — pure text transformation.
  class MathNormalizer
    GREEK = {
      "α" => "alpha", "β" => "beta", "γ" => "gamma", "δ" => "delta",
      "ε" => "epsilon", "ζ" => "zeta", "η" => "eta", "θ" => "theta",
      "ι" => "iota", "κ" => "kappa", "λ" => "lambda", "μ" => "mu",
      "ν" => "nu", "ξ" => "xi", "π" => "pi", "ρ" => "rho",
      "σ" => "sigma", "τ" => "tau", "φ" => "phi", "χ" => "chi",
      "ψ" => "psi", "ω" => "omega",
      "Γ" => "Gamma", "Δ" => "Delta", "Θ" => "Theta", "Λ" => "Lambda",
      "Ξ" => "Xi", "Π" => "Pi", "Σ" => "Sigma", "Φ" => "Phi",
      "Ψ" => "Psi", "Ω" => "Omega"
    }.freeze

    GREEK_CHARS_RE = /[#{GREEK.keys.join}]/.freeze
    GREEK_CLASS_RE = "[#{GREEK.keys.join}]"

    # Order matters: process the greedier multi-index pattern before
    # the simple single-subscript pattern.
    MULTI_INDEX_RE = /stem:\[([^\]]+)\]~([^~]+),~stem:\[([^\]]+)\]/.freeze
    SUBSCRIPT_RE    = /stem:\[([^\]]+)\]~([^~]+)~/.freeze
    SUPERSCRIPT_RE  = /stem:\[([^\]]+)\]\^([^^]+)\^/.freeze
    GREEK_BEFORE_RE = /(#{GREEK_CLASS_RE})stem:\[([^\]]+)\]/.freeze

    class << self
      # Normalize a string in place. Returns the (possibly) modified string.
      def normalize_text(text)
        return text unless text.is_a?(String)

        result = text.dup

        # 1. Multi-index: stem:[X]~Y,~stem:[Z] → stem:[X_(Y,Z)]
        #    Run iteratively in case there are chains.
        loop do
          new = result.gsub(MULTI_INDEX_RE) do
            inner, sub, tail = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)
            full = normalize_inside("#{sub},#{tail}")
            "stem:[#{fold_subscript(inner, full)}]"
          end
          break if new == result
          result = new
        end

        # 2. Simple subscript: stem:[X]~Y~ → stem:[X_Y]
        result.gsub!(SUBSCRIPT_RE) do
          inner, sub = Regexp.last_match(1), Regexp.last_match(2)
          sub_norm = normalize_inside(sub)
          "stem:[#{fold_subscript(inner, sub_norm)}]"
        end

        # 3. Simple superscript: stem:[X]^Y^ → stem:[X^Y]
        result.gsub!(SUPERSCRIPT_RE) do
          inner, sup = Regexp.last_match(1), Regexp.last_match(2)
          sup_norm = normalize_inside(sup)
          "stem:[#{fold_superscript(inner, sup_norm)}]"
        end

        # 4. Greek immediately before stem: Δstem:[X] → stem:[Delta X]
        result.gsub!(GREEK_BEFORE_RE) do
          greek, inner = Regexp.last_match(1), Regexp.last_match(2)
          "stem:[#{GREEK[greek]} #{normalize_inside(inner)}]"
        end

        # 5. Unicode Greek INSIDE any stem block → AsciiMath names.
        result = normalize_greek_inside_stem(result)

        result
      end

      # Fold a subscript into existing stem content. Two cases:
      #   inner ends with `_(...)`  → append to existing subscript
      #     e.g. "E_(e,)" + "λ" → "E_(e, λ)"
      #   otherwise               → add new subscript
      #     e.g. "L" + "e" → "L_e"
      #     e.g. "L" + "et" → "L_(et)"  (multi-char wrapped)
      def fold_subscript(inner, sub)
        if inner =~ /\A(.*)_\(([^)]*)\)\z/
          prefix, existing = Regexp.last_match(1), Regexp.last_match(2)
          stripped = existing.sub(/,\s*\z/, "")
          if stripped.empty?
            "#{prefix}_(#{sub})"
          else
            "#{prefix}_(#{stripped}, #{sub})"
          end
        else
          "#{inner}_#{wrap_if_multi(sub)}"
        end
      end

      # Same pattern for superscripts.
      def fold_superscript(inner, sup)
        if inner =~ /\A(.*)\^\(([^)]*)\)\z/
          prefix, existing = Regexp.last_match(1), Regexp.last_match(2)
          stripped = existing.sub(/,\s*\z/, "")
          if stripped.empty?
            "#{prefix}^(#{sup})"
          else
            "#{prefix}^(#{stripped}, #{sup})"
          end
        else
          "#{inner}^#{wrap_if_multi(sup)}"
        end
      end

      # Wrap multi-char subscripts/superscripts in parens so AsciiMath
      # treats them as a single subscript/superscript rather than a
      # single letter followed by trailing text.
      #   L_e    → L_e      (single char, no parens)
      #   L_(e,t)→ L_(e,t)  (already parens, no double-wrap)
      #   L_et   → L_(et)   (multi-char, no existing parens)
      def wrap_if_multi(str)
        return str if str.length <= 1
        return str if str.start_with?("(") && str.end_with?(")")
        "(#{str})"
      end

      # Walk a YAML concept structure, normalizing every string value.
      # Returns true if any change was made. Mutates +hash+ in place.
      def normalize_hash!(hash)
        changed = false
        hash.each do |k, v|
          case v
          when String
            new = normalize_text(v)
            if new != v
              hash[k] = new
              changed = true
            end
          when Hash  then changed |= normalize_hash!(v)
          when Array then changed |= normalize_array!(v)
          end
        end
        changed
      end

      def normalize_array!(arr)
        changed = false
        arr.each_with_index do |v, i|
          case v
          when String
            new = normalize_text(v)
            if new != v
              arr[i] = new
              changed = true
            end
          when Hash  then changed |= normalize_hash!(v)
          when Array then changed |= normalize_array!(v)
          end
        end
        changed
      end

      private

      def normalize_greek_inside_stem(text)
        text.gsub(/stem:\[([^\]]+)\]/) do
          inner = Regexp.last_match(1)
          "stem:[#{normalize_inside(inner)}]"
        end
      end

      def normalize_inside(str)
        str.gsub(GREEK_CHARS_RE) { |c| GREEK[c] }
      end
    end
  end
end
