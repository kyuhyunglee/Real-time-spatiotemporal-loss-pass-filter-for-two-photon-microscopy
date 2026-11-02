classdef TiffFrameSource < handle
    %TIFFRAMESOURCE
    % Multipage TIFF 또는 단일 TIFF 파일을 프레임 단위로 읽는 입력 소스
    % 나중에 Link 이후에도 똑같은 형태로 제공하면 된다
    % hasNextFrame()
    % nextFrame()
    % reset()
    % getFrameCount()

    properties (SetAccess = private)
        FilePath
        FileInfo
        NumFrames
        CurrentIndex
        FrameRate
    end

    methods
        function obj = TiffFrameSource(filePath, frameRate)
            % 생성자

            if nargin < 2
                frameRate = 30;
            end

            filePath = string(filePath);

            if ~isfile(filePath)
                error("TiffFrameSource:FileNotFound",...
                    "TIF 파일을 찾을 수 없습니다: %s", filePath);
            end

            if frameRate <= 0
                error("frameRate은 0보다 커야 합니다.");
            end

            obj.FilePath = filePath;
            obj.FileInfo = imfinfo(filePath);
            obj.NumFrames = numel(obj.FileInfo);
            obj.CurrentIndex = 1;
            obj.FrameRate = frameRate;

            fprintf("TIF source initialized.\n");
            fprintf("  File: %s\n", obj.FilePath);
            fprintf("  Number of frames: %d\n", obj.NumFrames);
            fprintf("  Image size: %d x %d\n", ...
                obj.FileInfo(1).Height, obj.FileInfo(1).Width);
            fprintf("  Simulated frame rate: %.3f fps\n", obj.FrameRate);
        end

        function tf = hasNextFrame(obj)
            % 다음으로 아직 읽을 프레임이 남아 있으면 true
            tf = obj.CurrentIndex <= obj.NumFrames;
        end

        function [frame, metadata] = nextFrame(obj)
            % 다음 TIFF 페이지를 한 프레임으로 반환

            if ~obj.hasNextFrame()
                error("TiffFrameSource:NoMoreFrames",...
                    "어 이상 읽을 프레임이 없습니다.");
            end

            frameIndex = obj.CurrentIndex;

            frame = imread(...
                obj.FilePath, ...
                frameIndex, ...
                "Info", obj.FileInfo);

            % multichannel 파일, ex) RGB 파일이 들어오는 예외처리
            if ndims(frame) == 3
                if size(frame, 3) == 3
                    frame = mean(single(frame),3);
                else
                    error("지원하지 않는 TIFF 채널 구조입니다.");
                end
            end

            metadata = struct();
            metadata.frameIndex = frameIndex;
            metadata.timestampSeconds = ...
                (frameIndex - 1) / obj.FrameRate;
            metadata.sourceFile = obj.FilePath;
            metadata.originalClass = class(frame);
            metadata.originalSize = size(frame);

            obj.CurrentIndex = obj.CurrentIndex + 1;
        end

        function reset(obj)
            % 처음 프레임부터 다시 읽도록 초기화
            obj.CurrentIndex = 1;
        end

        function count = getFrameCount(obj)
            count = obj.NumFrames;
        end
    end
end