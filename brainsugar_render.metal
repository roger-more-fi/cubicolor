//
//  brainsugar_render.metal
//  created by Harri Hilding Smatt on 2025-12-28
//

#include <metal_stdlib>
using namespace metal;

struct share_struct
{
    float4 position [[position]];
    float2 position_rel;
    float4 color;
};

vertex share_struct clear_vs(const uint32_t vertex_id [[ vertex_id ]])
{
    share_struct out;
    out.position_rel = float2((vertex_id >> 1), (vertex_id & 1));
    out.position = float4(out.position_rel * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 clear_fs(const share_struct shared [[ stage_in ]],
                         const texture2d<float> tx [[ texture(0) ]])
{
    constexpr sampler tx_sampler(mag_filter::nearest, min_filter::nearest);
    const float3 tex = tx.sample(tx_sampler, float2(0.8 - pow(0.2 + shared.position_rel.y, 4.0),
                                                    pow(shared.position_rel.x, 3.0))).rgb;
    return float4(tex * float3(0.6, 0.7, 0.92), 0.1);
}

vertex share_struct copy_vs(const uint32_t vertex_id [[ vertex_id ]])
{
    share_struct out;
    out.position_rel = float2((vertex_id >> 1), (vertex_id & 1));
    out.position = float4(float2(0.0 + out.position_rel.x, 1.0 - out.position_rel.y) * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 copy_fs(const share_struct shared [[ stage_in ]],
                        const device float3* tap_positions [[ buffer(0) ]],
                        const texture2d<float> tx [[ texture(0) ]],
                        const depth2d<float> dp [[ texture(1) ]])
{
    constexpr sampler texture_sampler(mag_filter::bicubic, min_filter::bicubic);
    
    float tex_mul = 1.0;
    float2 tex_pos = shared.position_rel;
    for (int index = 0; index < 20; ++index) {
        const float3 tap_pos = tap_positions[index];
        const float tap_dist = 1.0 - (1.0 - distance(shared.position_rel, tap_pos.xy) * (abs(tap_pos.z) > 0.0));
        const bool is_within_tap_dist = (tap_pos.z > 0.0 || tap_dist > (0.2 + tap_pos.z * 0.2)) && tap_dist <= 0.2;
        tex_mul *= 1.0 - (1.0 - saturate(5.0 * tap_dist)) * is_within_tap_dist;
        tex_pos += ((shared.position_rel - tap_pos.xy) * 0.05 * pow(tex_mul, -1.75)) * is_within_tap_dist;
    }
    
    const float dp_val = dp.sample(texture_sampler, shared.position_rel);
    const float4 tx_col = tx.sample(texture_sampler, tex_pos);
    return float4(pow(dp_val, 4.0) * tx_col.rgb * saturate(0.5 + 0.5 * sqrt(tex_mul)), 1.0);
}

vertex share_struct environment_vs(const device float4x4& model_m [[ buffer(0) ]],
                                   const device float4x4& view_m [[ buffer(1) ]],
                                   const device float4x4& proj_m [[ buffer(2) ]],
                                   const uint32_t vertex_id [[ vertex_id ]],
                                   const uint32_t instance_id [[ instance_id ]])
{
    const uint i_0 = (instance_id >> 1) & 1;
    const uint i_1 = (((instance_id + 1) >> 1) & 1);
    const uint v_0 = (vertex_id >> 1) & 1;
    const uint v_1 = ((vertex_id + 1) >> 1) & 1;
    const uint i_1_v_1 = !i_1 ^ v_1;
    const float3 pos = float3( (int3(i_1_v_1, v_0, i_1) & (i_0 ^ 1)) |
                               (int3(i_1, v_0 ^ 1, i_1_v_1 ^ 1) & i_0));
       
    share_struct out;
    out.position = proj_m * view_m *
                    (float4(1.0, 1.0, 0.01, 1.0) *
                     (model_m * float4(pos * 2.0 - 1.0, 1.0)));
    out.color = float4(0.2, 0.2, 0.2, 0.2);
    out.color[(instance_id + vertex_id) & 3] = 1.0;
    return out;
}

fragment float4 environment_fs(const share_struct shared [[ stage_in ]])
{
    const float r = sqrt(length(shared.position_rel.xy) * 0.5);
    const float d = length(shared.position.xyz / shared.position.w);
    return saturate(float4(1.5 * float3(r * normalize(shared.color.rgb)), pow(abs(sin(d + r)), 7.0)));
}
