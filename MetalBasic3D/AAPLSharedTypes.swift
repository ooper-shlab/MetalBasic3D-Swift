//
//  AAPLSharedTypes.swift
//  MetalBasic3D
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/14.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Shared data types between CPU code and metal shader code
 */

import simd

extension AAPL {
    struct constants_t {
        var modelview_projection_matrix: float4x4
        var normal_matrix: float4x4
        var ambient_color: float4
        var diffuse_color: float4
        var multiplier: Int32
        //### to make aligned to 256
        private var _dummy4: Int32 = 0
        private var _dummy8: float2 = float2()
        private var _dummy16: float4 = float4()
        private var _dummy64: float4x4 = float4x4()
    }
}

