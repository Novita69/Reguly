import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const { data: rawData, error } = await supabase.from("v_weekly_activity_aggregates").select("*");
    if (error) throw error;
    if (!rawData || rawData.length < 8) {
      await logRun(supabase, { status: "insufficient_data", total_observations: rawData?.length ?? 0, selected_k: 0, sse_values: {}, centroids: [], normalization: {} });
      return new Response(JSON.stringify({ message: "Insufficient data", count: rawData?.length }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const features = rawData.map((r: any) => [r.x1_frequency??0, r.x2_avg_duration??0, r.x3_avg_focus??0, r.x4_consistency??0, r.x5_progress??0]);
    const userWeeks = rawData.map((r: any) => ({ user_id: r.user_id, week_start: r.week_start }));
    const { normalizedFeatures, normParams } = minMaxNormalize(features);
    const maxK = Math.min(6, rawData.length - 1);
    const sseValues: Record<string, number> = {};
    for (let k = 2; k <= maxK; k++) sseValues[`k${k}`] = runKMeans(normalizedFeatures, k, 100, 42).sse;
    const selectedK = findElbowK(sseValues);
    const finalResult = runKMeans(normalizedFeatures, selectedK, 300, 42);
    const runId = await logRun(supabase, { status: "success", total_observations: rawData.length, selected_k: selectedK, sse_values: sseValues, centroids: finalResult.centroids, normalization: normParams });
    await updatePersonaHistory(supabase, userWeeks, finalResult, runId, features);
    await generateRecommendations(supabase, runId);
    return new Response(JSON.stringify({ success: true, selected_k: selectedK, total_observations: rawData.length }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});

function minMaxNormalize(data: number[][]): { normalizedFeatures: number[][]; normParams: Record<string, number> } {
  const m = data[0].length;
  const mins = Array(m).fill(Infinity), maxs = Array(m).fill(-Infinity);
  for (const row of data) for (let j = 0; j < m; j++) { mins[j]=Math.min(mins[j],row[j]); maxs[j]=Math.max(maxs[j],row[j]); }
  const normalizedFeatures = data.map(row => row.map((v,j) => maxs[j]-mins[j]===0 ? 0 : (v-mins[j])/(maxs[j]-mins[j])));
  const normParams: Record<string,number> = {};
  ["x1","x2","x3","x4","x5"].forEach((n,j) => { normParams[`${n}_min`]=mins[j]; normParams[`${n}_max`]=maxs[j]; });
  return { normalizedFeatures, normParams };
}
function euclidean(a: number[], b: number[]): number { return Math.sqrt(a.reduce((s,v,i)=>s+(v-b[i])**2,0)); }
function runKMeans(data: number[][], k: number, maxIter: number, seed: number) {
  const n=data.length, m=data[0].length;
  const centroids=initKMeans(data,k,seed);
  let assignments=new Array(n).fill(0), prev=new Array(n).fill(-1);
  for(let iter=0;iter<maxIter;iter++){
    for(let i=0;i<n;i++){let md=Infinity,mc=0;for(let j=0;j<k;j++){const d=euclidean(data[i],centroids[j]);if(d<md){md=d;mc=j;}}assignments[i]=mc;}
    if(assignments.every((a,i)=>a===prev[i]))break;
    prev=[...assignments];
    for(let j=0;j<k;j++){const ms=data.filter((_,i)=>assignments[i]===j);if(ms.length===0)continue;centroids[j]=Array(m).fill(0).map((_,fi)=>ms.reduce((s,r)=>s+r[fi],0)/ms.length);}
  }
  return { centroids, assignments, sse: data.reduce((s,p,i)=>s+euclidean(p,centroids[assignments[i]])**2,0) };
}
function initKMeans(data: number[][], k: number, seed: number): number[][] {
  const n=data.length, cs=[data[seed%n]];
  for(let i=1;i<k;i++){
    const ds=data.map(p=>Math.min(...cs.map(c=>euclidean(p,c))));
    const tot=ds.reduce((a,b)=>a+b,0);
    let cum=0,thr=(seed*i*0.7654321)%tot,cho=data[(seed*i)%n];
    for(let j=0;j<n;j++){cum+=ds[j];if(cum>=thr){cho=data[j];break;}}
    cs.push(cho);
  }
  return cs;
}
function findElbowK(sse: Record<string,number>): number {
  const ks=Object.keys(sse).sort();
  if(ks.length<3)return parseInt(ks[0].replace("k",""))||2;
  const ss=ks.map(k=>sse[k]);
  let mx=0,idx=1;
  for(let i=1;i<ss.length-1;i++){const d=ss[i-1]-2*ss[i]+ss[i+1];if(d>mx){mx=d;idx=i;}}
  return parseInt(ks[idx].replace("k",""));
}
function label(c: number[], all: number[][]): string {
  const k=all.length, avg=Array(5).fill(0).map((_,i)=>all.reduce((s,x)=>s+x[i],0)/k);
  const hi=(v:number,a:number)=>v>a*1.1, lo=(v:number,a:number)=>v<a*0.9;
  const [x1,,x3,x4,x5]=c,[ax1,,ax3,ax4,ax5]=avg;
  if(hi(x1,ax1)&&hi(x4,ax4)&&hi(x5,ax5)&&!lo(x3,ax3))return"consistent";
  if(lo(x1,ax1)&&lo(x4,ax4)&&lo(x5,ax5))return"passive";
  if(lo(x4,ax4)&&!lo(x1,ax1))return"seasonal";
  return"ambitious";
}
async function logRun(sb: any, d: any): Promise<string|null> {
  const {data:r,error}=await sb.from("clustering_runs").insert({selected_k:d.selected_k,sse_values:d.sse_values,centroids:d.centroids,normalization:d.normalization,total_observations:d.total_observations,status:d.status,random_seed:42}).select("id").single();
  if(error)console.error(error);
  return r?.id??null;
}
async function updatePersonaHistory(sb: any, uws: any[], res: any, runId: string|null, features: number[][]) {
  const uids=[...new Set(uws.map((u:any)=>u.user_id))];
  await sb.from("persona_history").update({is_current:false}).in("user_id",uids);
  const {data:run}=await sb.from("clustering_runs").select("centroids").eq("id",runId).single();
  const cs=run?.centroids??[];
  for(let i=0;i<uws.length;i++){
    const cn=res.assignments[i],c=cs[cn]??[],lbl=label(c,cs);
    await sb.from("persona_history").upsert({user_id:uws[i].user_id,week_start:uws[i].week_start,clustering_run_id:runId,cluster_number:cn,persona_label:lbl,persona_label_id:lbl,feature_values:{x1:features[i][0],x2:features[i][1],x3:features[i][2],x4:features[i][3],x5:features[i][4]},centroid_values:{x1:c[0]??0,x2:c[1]??0,x3:c[2]??0,x4:c[3]??0,x5:c[4]??0},is_current:true},{onConflict:"user_id,week_start"});
  }
}
async function generateRecommendations(sb: any, runId: string | null) {
  const { data: ps } = await sb
    .from("persona_history")
    .select("id, user_id, persona_label_id, feature_values")
    .eq("is_current", true);
  if (!ps) return;

  for (const p of ps) {
    const { data: rules } = await sb
      .from("recommendation_rules")
      .select("*")
      .eq("persona_label_id", p.persona_label_id)
      .eq("is_active", true);
    if (!rules) continue;

    const values = formatMetrics(p.feature_values ?? {});

    const rows = rules.map((r: any) => {
      const insightFilled = substitutePlaceholders(r.ai_insight, values);
      const actionFilled = substitutePlaceholders(r.action, values);
      return {
        user_id: p.user_id,
        persona_history_id: p.id,
        rule_id: r.id,
        msr_dimension: r.msr_dimension,
        title: r.title,
        ai_insight: hasUnresolvedPlaceholder(insightFilled)
          ? logAndFallback(insightFilled, p.user_id, r.id, "ai_insight")
          : insightFilled,
        strategy: r.strategy,
        action: hasUnresolvedPlaceholder(actionFilled)
          ? logAndFallback(actionFilled, p.user_id, r.id, "action")
          : actionFilled,
        reflection_question: r.reflection_question,
      };
    });

    await sb.from("recommendations").delete().eq("user_id", p.user_id);
    await sb.from("recommendations").insert(rows);
  }
}

// ----------------------------------------------------------------------------
// Substitusi placeholder [x1]-[x5] pada ai_insight/action dengan nilai asli
// dari feature_values milik user (sudah tersimpan di persona_history, tidak
// perlu query tambahan ke v_weekly_activity_aggregates).
// ----------------------------------------------------------------------------
function formatMetrics(fv: Record<string, number>): Record<string, string> {
  return {
    x1: String(Math.round(fv.x1 ?? 0)),
    x2: String(Math.round(fv.x2 ?? 0)),
    x3: (fv.x3 ?? 0).toFixed(1),
    x4: String(Math.round(fv.x4 ?? 0)),
    x5: String(Math.round(fv.x5 ?? 0)),
  };
}
function substitutePlaceholders(template: string, values: Record<string, string>): string {
  let result = template;
  for (const [key, value] of Object.entries(values)) {
    result = result.replace(new RegExp(`\\[${key}\\]`, "g"), value);
  }
  return result;
}
function hasUnresolvedPlaceholder(text: string): boolean {
  return /\[x[1-5]\]/.test(text);
}
function logAndFallback(text: string, userId: string, ruleId: string, field: string): string {
  console.error(`Placeholder tidak terselesaikan user=${userId} rule=${ruleId} field=${field}: "${text}"`);
  return "Rekomendasi sedang diperbarui. Silakan cek kembali beberapa saat lagi.";
}
