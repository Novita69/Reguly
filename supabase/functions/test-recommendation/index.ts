import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { generateRecommendationsForUser } from "../run-kmeans/generate_recommendations.ts";

serve(async (req) => {
    try {
        const { userId, personaLabelId, periodStart, personaHistoryId } = await req.json();

        const supabase = createClient(
            Deno.env.get("SUPABASE_URL")!,
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
        );

        const result = await generateRecommendationsForUser(supabase, {
            userId,
            personaLabelId,
            periodStart,
            personaHistoryId,
        });

        return new Response(JSON.stringify({ success: true, result }), {
            headers: { "Content-Type": "application/json" },
        });
    } catch (error: any) {
        return new Response(JSON.stringify({ success: false, error: error.message }), {
            status: 500,
            headers: { "Content-Type": "application/json" },
        });
    }
});