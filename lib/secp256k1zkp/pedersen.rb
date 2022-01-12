# frozen_string_literal: true

module Secp256k1zkp

  module Pedersen

    # Pedersen commitment
    class Commitment < FFI::Struct

      layout :data, [:uchar, 64]

      SIZE = 33 # The size of a Pedersen commitment
      SIZE_INTERNAL = 64 # The size of a Pedersen commitment

      # Generate a Pedersen commitment.
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @param [Integer] value value to commit to.
      # @param [Integer] blind blinding factor.
      # @param [Secp256k1zkp::Generator] value_gen value generator 'h'
      # @param [Secp256k1zkp::Generator] blind_gen blinding factor generator 'g'
      # @return [Secp256k1zkp::Pedersen::Commitment]
      # @raise [ArgumentError]
      # @raise [Secp256k1zkp::InvalidFactor]
      def self.generate(ctx, value, blind, value_gen: Secp256k1zkp.generator_h_ptr, blind_gen: Secp256k1zkp.generator_g_ptr)
        raise ArgumentError unless blind.is_a?(Integer)
        raise ArgumentError unless value.is_a?(Integer)

        commitment = Commitment.new
        raw_blind = [blind.to_even_hex(32)].pack('H*')
        raw_blind_ptr = FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, raw_blind)
        res = C.secp256k1_pedersen_commit(ctx.ctx, commitment.pointer, raw_blind_ptr, value, value_gen, blind_gen)
        raise InvalidFactor unless res == 1

        commitment
      end

      # Parse a 33-bytes commitment into a commitment object.
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @param [String] hex_commitment 33-bytes serialized commitment key.
      # @return [Secp256k1zkp::Pedersen::Commitment]
      # @raise [Secp256k1zkp::InvalidCommit]
      def self.from_hex(ctx, hex_commitment)
        raw_commit = [hex_commitment].pack('H*')
        raise InvalidCommit if raw_commit.bytesize != SIZE || raw_commit.unpack1('H*') != hex_commitment

        commit_ptr = FFI::MemoryPointer.new(:uchar, SIZE).put_bytes(0, raw_commit)
        commitment = Commitment.new
        res = C.secp256k1_pedersen_commitment_parse(ctx.ctx, commitment.pointer, commit_ptr)
        raise InvalidCommit unless res == 1

        commitment
      end

      # Computes the sum of multiple positive and negative blinding factors.
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @param [Array(Integer)] positives array of positive blind factors
      # @param [Array(Integer)] negatives array of negative blind factors
      def self.blind_sum(ctx, positives, negatives)
        raise ArgumentError, 'positives should be Array(Integer)' unless positives.is_a?(Array)
        raise ArgumentError, 'negatives should be Array(Integer)' unless positives.is_a?(Array)

        blind_count = positives.length + negatives.length
        all = FFI::MemoryPointer.new(:pointer, blind_count)
        (positives + negatives).each_with_index do |blind, i|
          raise ArgumentError 'blinding factor should be Integer' unless blind.is_a?(Integer)

          raw_blind = [blind.to_even_hex(32)].pack('H*')
          all[i].put_pointer(0, FFI::MemoryPointer.new(:uchar, 32).put_bytes(0, raw_blind))
        end
        sum = FFI::MemoryPointer.new(:uchar, 32)
        res = C.secp256k1_pedersen_blind_sum(ctx.ctx, sum, all, blind_count, positives.length)
        raise AssertError, 'secp256k1_pedersen_blind_sum failed' unless res == 1

        sum.read_bytes(32).unpack1('H*').to_i(16)
      end

      # Computes the sum of multiple positive and negative pedersen commitments
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @param [Array(Secp256k1zkp::Pedersen::Commitment)] positives array of positive commitments
      # @param [Array(Secp256k1zkp::Pedersen::Commitment)] negatives array of negative commitments
      # @return [Secp256k1zkp::Pedersen::Commitment]
      # @raise [Secp256k1zkp::IncorrectCommitSum]
      def self.commit_sum(ctx, positives, negatives)
        positive_ptr = FFI::MemoryPointer.new(:pointer, positives.length)
        negative_ptr = FFI::MemoryPointer.new(:pointer, positives.length)
        positives.each_with_index do |commit, i|
          positive_ptr[i].put_pointer(0, commit.pointer)
        end
        negatives.each_with_index do |commit, i|
          negative_ptr[i].put_pointer(0, commit.pointer)
        end
        commit = Commitment.new
        res = C.secp256k1_pedersen_commit_sum(ctx.ctx, commit.pointer, positive_ptr, positives.length, negative_ptr, negatives.length)
        raise IncorrectCommitSum unless res == 1

        commit
      end

      # Verify a tally of Pedersen commitments
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @param [Array(Secp256k1zkp::Pedersen::Commitment)] positives array of positive commitments
      # @param [Array(Secp256k1zkp::Pedersen::Commitment)] negatives array of negative commitments
      # @return [Boolean]
      def self.valid_commit_sum?(ctx, positives, negatives)
        positive_ptr = FFI::MemoryPointer.new(:pointer, positives.length)
        positives.each_with_index { |commit, i| positive_ptr[i].put_pointer(0, commit.pointer) }
        negative_ptr = FFI::MemoryPointer.new(:pointer, negatives.length)
        negatives.each_with_index { |commit, i| negative_ptr[i].put_pointer(0, commit.pointer) }

        res = C.secp256k1_pedersen_verify_tally(ctx.ctx, positive_ptr, positives.length, negative_ptr, negatives.length)
        res == 1
      end

      # Convert commitment to a serialized hex string.
      # @param [Secp256k1zkp::Context] ctx Secp256k1 context.
      # @return [String] hex string.
      def to_hex(ctx)
        hex_ptr = FFI::MemoryPointer.new(:uchar, SIZE)

        C.secp256k1_pedersen_commitment_serialize(ctx.ctx, hex_ptr, pointer)
        hex_ptr.read_bytes(SIZE).unpack1('H*')
      end

      # Override +==+ to check whether same public key or not.
      # @param [Secp256k1zkp::Pedersen::Commitment] other
      # @return [Boolean]
      def ==(other)
        return false unless other.is_a?(Commitment)

        self[:data].to_a == other[:data].to_a
      end
    end

  end
end
