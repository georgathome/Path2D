classdef NumelTest < matlab.unittest.TestCase
    
    properties (TestParameter)
        PathEmpty = struct(...
            'PolygonPath', PolygonPath(), ...
            'SplinePath', SplinePath())
        
        PathNonEmpty = {
            {PolygonPath.xy2Path(0:10, zeros(1,11)), 11};
            {SplinePath([0 1 2], reshape([1 0; 0 0; 1 1; 1 0], 2,2,2)), 2};
            }
    end
    
    
    
    methods (Test)
        
        function testPathEmpty(testCase, PathEmpty)
            verifyEqual(testCase, PathEmpty.numel(), 0);
        end%fcn
        
        function testPathNonEmpty(testCase, PathNonEmpty)
            PathObj = PathNonEmpty{1};
            NExp = PathNonEmpty{2};
            
            verifyEqual(testCase, PathObj.numel(), NExp);
        end%fcn
        
    end
    
end%class
