/***************************************************************************
 # Copyright (c) 2020-2021, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#pragma pack_matrix(row_major)

#include "RtxdiApplicationBridge.hlsli"

// Only enable the boiling filter for RayQuery (compute shader) mode because it requires shared memory
#if USE_RAY_QUERY
#define RTXDI_ENABLE_BOILING_FILTER
#define RTXDI_BOILING_FILTER_GROUP_SIZE RTXDI_SCREEN_SPACE_GROUP_SIZE
#endif

#include <rtxdi/ResamplingFunctions.hlsli>

#if USE_RAY_QUERY
[numthreads(RTXDI_SCREEN_SPACE_GROUP_SIZE, RTXDI_SCREEN_SPACE_GROUP_SIZE, 1)] 
void main(uint2 GlobalIndex : SV_DispatchThreadID, uint2 LocalIndex : SV_GroupThreadID)
#else
[shader("raygeneration")]
void RayGen()
#endif
{
#if !USE_RAY_QUERY
    uint2 GlobalIndex = DispatchRaysIndex().xy;
#endif

    const RTXDI_ResamplingRuntimeParameters params = g_Const.runtimeParams;

    uint2 pixelPosition = RTXDI_ReservoirToPixelPos(GlobalIndex, params);

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(pixelPosition, 2);

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);

    RTXDI_Reservoir temporalResult = RTXDI_EmptyReservoir();
    
    if (RAB_IsSurfaceValid(surface))
    {
        RTXDI_Reservoir curSample = RTXDI_LoadReservoir(params, u_LightReservoirs, 
            GlobalIndex, g_Const.initialOutputBufferIndex);

        RTXDI_TemporalResamplingParameters tparams;
        tparams.screenSpaceMotion = t_MotionVectors[pixelPosition].xyz;
        tparams.sourceBufferIndex = g_Const.temporalInputBufferIndex;
        tparams.maxHistoryLength = g_Const.maxHistoryLength;
        tparams.biasCorrectionMode = g_Const.temporalBiasCorrection;
        tparams.depthThreshold = g_Const.temporalDepthThreshold;
        tparams.normalThreshold = g_Const.temporalNormalThreshold;

        temporalResult = RTXDI_TemporalResampling(pixelPosition, surface, curSample,
            rng, tparams, params, u_LightReservoirs);
    }

#ifdef RTXDI_ENABLE_BOILING_FILTER
    if (g_Const.boilingFilterStrength > 0)
    {
        RTXDI_BoilingFilter(LocalIndex, g_Const.boilingFilterStrength, params, temporalResult);
    }
#endif

    RTXDI_StoreReservoir(temporalResult, params, u_LightReservoirs, GlobalIndex, g_Const.temporalOutputBufferIndex);
}