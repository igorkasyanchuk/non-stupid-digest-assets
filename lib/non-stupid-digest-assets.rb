module NonStupidDigestAssets
  mattr_accessor :whitelist
  @@whitelist = []
end

module OldSprockets
  def compile(*args)
    unless environment
      raise Error, "manifest requires environment for compilation"
    end

    paths = environment.each_logical_path(*args).to_a +
      args.flatten.select { |fn| Pathname.new(fn).absolute? if fn.is_a?(String)}

    paths.each do |path|
      if asset = find_asset(path)
        files[asset.digest_path] = {
          'logical_path' => asset.logical_path,
          'mtime'        => asset.mtime.iso8601,
          'size'         => asset.bytesize,
          'digest'       => asset.digest
        }
        logical_path = asset.logical_path
        assets[asset.logical_path] = asset.digest_path

        target = File.join(dir, asset.digest_path)

        if File.exist?(target)
          logger.debug "Skipping #{target}, already exists"
        else
          logger.info "Writing #{target}"
          asset.write_to target
          asset.write_to "#{target}.gz" if asset.is_a?(BundledAsset)
        end

        if ENV['SPROCKETS_NON_DIGEST']
          logical_target = File.join(dir, logical_path)
          logger.info "Writing #{logical_target}"
          asset.write_to logical_target
          asset.write_to "#{logical_target}.gz" if asset.is_a?(BundledAsset)
        end

        save
        asset
      end
    end
  end
end

module Sprockets
  class Manifest
    unless respond_to?(:compile)
      include OldSprockets
    end

    def compile_with_non_digest *args
      compile_without_non_digest *args
      if NonStupidDigestAssets.whitelist.empty?
        files_to_copy = files
      else
        files_to_copy = files.select do |file, info|
          !NonStupidDigestAssets.whitelist.detect do |item|
            info['logical_path'] =~ /#{item}/
          end.nil?
        end
      end
      files_to_copy.each do |(digest_path, info)|
        full_digest_path = File.join dir, digest_path
        full_digest_gz_path = "#{full_digest_path}.gz"
        full_non_digest_path = File.join dir, info['logical_path']
        full_non_digest_gz_path = "#{full_non_digest_path}.gz"

        if File.exists? full_digest_path
          logger.info "Writing #{full_non_digest_path}"
          FileUtils.cp full_digest_path, full_non_digest_path
        else
          logger.warn "Could not find: #{full_digest_path}"
        end
        if File.exists? full_digest_gz_path
          logger.info "Writing #{full_non_digest_gz_path}"
          FileUtils.cp full_digest_gz_path, full_non_digest_gz_path
        else
          logger.warn "Could not find: #{full_digest_gz_path}"
        end
      end
    end

    alias_method_chain :compile, :non_digest
  end
end
