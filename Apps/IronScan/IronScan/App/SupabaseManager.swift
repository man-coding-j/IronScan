import Foundation
import Supabase

enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://xthrnjxgphrfpdyrapqx.supabase.co")
            ?? URL(fileURLWithPath: "/invalid-supabase-url"),
        supabaseKey: "sb_publishable_YhzPYgXv7LFWHUr0Baxi4w_CtllQ_Gi",
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}