#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# rescue.rb

require 'optparse'
require 'digest/sha2'
require 'fileutils'

class Digest::Base
    def self.open(path)
        obj = new

        File.open(path, 'rb') {|f|
            buf = ""
            while f.read(1024*1024, buf)
                obj << buf
            end
        }
        obj
    end
end

class FileInfo
    def initialize(filename, size, hash)
        @filename = filename
        @size = size
        @hash = hash
    end

    def to_s()
        return "%s\t%s\t%s"%[@filename, @size, @hash]
    end
end

class FileList
    @@instance = nil
    def FileList.create_instance(filename)
        @@instance = FileList.new(filename)
    end

    def FileList.get_instance()
        return @@instance
    end

    def initialize(filename)
        @filename = filename
        @list = {}

        load() if(File.exists?(filename)) 
    end

    def load()
        fp = open(@filename)
        
        fp.each_line do |line|
            arr = line.chomp.split("\t")
            add(arr[0], arr[1], arr[2])
        end

        fp.close()
    end

    def save()
        fp = open(@filename, "w")
        @list.each do |id, info|
            fp.puts(info.to_s())
        end
        fp.close()
    end

    def add(filename, size, hash)
        fi = FileInfo.new(filename, size, hash)
        @list[key(filename, size, hash)] = fi
    end

    def exists(filename, size, hash)
        return @list.has_key?(key(filename, size, hash))
    end

    def key(filename, size, hash)
        return hash.to_s + "::" + size.to_s
    end
end

class Pattern
    @@instance = nil
    def Pattern.create_instance(pattern)
        @@instance = Pattern.new(pattern)
    end
    
    def Pattern.get_instance()
        return @@instance
    end
    
    def initialize(pattern)
        @pattern = {}
        
        pattern.split(" ").each do |ptn|
            arr = ptn.split(":")
            size = 0
            if(arr.size == 2) then
                size = arr[1].to_i
                if arr[1].index("M") then
                    size = size * 1024 * 1024
                elsif arr[1].index("K") then
                    size = size * 1024
                end
            end
            @pattern["." + arr[0]] = size
        end
    end

    def match(path)
        ext = File.extname(path)
        return false if not @pattern.has_key?(ext)
        return File.size(path) >= @pattern[ext]
    end
end

class Log
    @@instance = nil
    def Log.create_instance(file)
        @@instance = Log.new(file)
    end

    def Log.get_instance()
        return @@instance
    end

    def initialize(file)
        @fp = open(file,"w")
    end

    def close()
        @fp.close()
    end

    def log(str)
        @fp.puts(str)
    end
end

def log(str)
    puts(str)
    Log.get_instance().log(str)
end

def process_directory(from_dir, to_dir)
    pattern = Pattern.get_instance()
    log("D: processing " + from_dir)
    arr = Dir.glob(from_dir + '/*')
    arr.sort.each{|path|
        if File.symlink?(path) then
            next
        elsif File.directory?(path) then
            process_directory(path, to_dir)
        elsif File.file?(path) then
            process_file(path, to_dir)
        end
    }
    log("D: leave " + from_dir)
end

def process_file(file, to_dir)
    m = Pattern.get_instance().match(file)
    filelist = FileList.get_instance()

    if m then
        filename = File.basename(file)
        size = File.size(file)
        hash = Digest::SHA256.open(file).hexdigest()

        if size > 4 * 1000 * 1000 * 1000 then
            log("F: skip %s (too big)" % file)
        elsif not filelist.exists(filename, size, hash) then
            dest_dir = to_dir + "/" + hash[0, 3] + "/"
            if not File.exists?(dest_dir) then
                Dir::mkdir(dest_dir)
            end
            dest = dest_dir + filename
            num = 1
            while File.exists?(dest) do
                dest = dest_dir
                dest += File.basename(filename, ".*") + "." + num.to_s
                dest += File.extname(filename)

                num += 1
            end

            FileUtils.cp(file, dest)

            filelist.add(filename, size, hash)
            
            log("F: copy %s => %s" % [file, dest])
        else
            log("F: skip %s (dup)" % file)
        end
    else
        #log("F: skip %s(unmatch)" % path)
    end
end

def main()
    opt = OptionParser.new
    listfile = "./list.txt"
    from_dir = './'
    to_dir = './'
    pattern_str = ''

    opt.on('-l list'){|v| listfile = v}
    opt.on('-f from_dir'){|v| from_dir = v}
    opt.on('-t to_dir'){|v| to_dir = v}
    opt.on('-p pattern'){|v| pattern_str = v }

    opt.parse!(ARGV)

    FileList.create_instance(listfile)
    Pattern.create_instance(pattern_str)
    Log.create_instance("./rescue.log")

    begin
        process_directory(from_dir, to_dir)
    rescue => e
        p e
    ensure
        FileList.get_instance().save()
    end
end

if __FILE__ == $0 then
    main()
end
