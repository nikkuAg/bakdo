import Foundation

/// Sentences the user reads aloud to build personal training data. They mirror real dictation:
/// casual Hinglish, work English, code-mixed sentences, Hindi-heavy speech, numbers and times.
/// Hindi is written in Roman script with the same spellings the speech model produces.
enum TrainingScript {
    static let sentences: [String] = [
        // Casual Hinglish
        "Yaar, aaj office mein bahut kaam tha, main thoda late ho jaunga.",
        "Kal shaam ko free ho kya? Chalo kahin bahar khana khaane chalte hain.",
        "Mummy ne bola hai ki ghar aate waqt doodh aur bread le aana.",
        "Bhai, tune woh movie dekhi? Mujhe toh kaafi achhi lagi.",
        "Main abhi meeting mein hoon, thodi der mein call karta hoon.",
        "Kya tum mujhe woh photos bhej sakte ho jo kal raat click ki thi?",
        "Aaj mausam bahut achha hai, chalo chai peene chalte hain.",
        "Mujhe nahi pata tha ki woh log itni jaldi pahunch jaayenge.",
        "Thik hai, main dekh leta hoon aur tumhe bata deta hoon.",
        "Arre, maine toh socha tha ki tum aaj chhutti par ho.",
        "Uska phone switch off aa raha hai, shayad battery khatam ho gayi.",
        "Weekend pe Goa jaane ka plan hai, tum bhi chaloge kya?",
        "Mera order abhi tak deliver nahi hua, main customer care ko call karta hoon.",
        "Sach bataun toh mujhe yeh idea pehle se hi pasand tha.",
        "Ghar pahunch ke message kar dena, raat ho gayi hai.",
        "Aaj gym nahi ja paaya, kal subah pakka jaunga.",
        "Didi ki shaadi agle mahine hai, sabko invite karna hai.",
        "Tumne lunch kiya? Main canteen ja raha hoon.",
        "Yeh wala restaurant bahut famous hai, yahan ka butter chicken try karna.",
        "Chalo phir, kal milte hain, bye.",
        "Mujhe lagta hai hume thoda aur wait karna chahiye.",
        "Itna traffic tha ki main ek ghante late pahuncha.",
        "Woh bol raha tha ki naya laptop lena hai, koi achha suggest karo.",
        "Bas paanch minute mein nikal raha hoon, wahin milte hain.",
        "Mere paas abhi time nahi hai, baad mein baat karte hain.",
        "Usne kaha ki report kal tak ready ho jaayegi.",
        "Kitna mast gaana hai yeh, repeat pe sun raha hoon.",
        "Kal raat neend hi nahi aayi, aaj bahut thakaan ho rahi hai.",
        "Ek kaam karo, mujhe location bhej do, main aa jaata hoon.",
        "Main soch raha tha ki is baar Diwali ghar pe hi manayein.",
        // Work English
        "Hey team, quick update on the launch: we are on track for Thursday.",
        "Can you please share the latest version of the presentation before the call?",
        "I have reviewed the pull request and left a few comments on the API changes.",
        "Let's schedule a meeting with the design team to finalize the onboarding flow.",
        "The client wants the invoice by end of day, so please prioritize it.",
        "I think we should run an A/B test before rolling this out to everyone.",
        "Thanks for the quick turnaround, this looks really good.",
        "Please make sure the database migration is tested on staging first.",
        "Our revenue grew by twenty percent this quarter compared to last year.",
        "Could you send me the meeting notes and the action items?",
        "I'm working from home today, ping me on Slack if anything is urgent.",
        "The deployment failed because of a missing environment variable.",
        "We need to hire two more backend engineers by the end of next month.",
        "Let me know if you have any questions or concerns about the proposal.",
        "I'll be on leave from the fifteenth to the twentieth, please plan accordingly.",
        "The dashboard is loading slowly, can someone look into the performance issue?",
        "Kindly find attached the signed agreement for your reference.",
        "Let's sync up tomorrow morning at ten thirty to discuss the roadmap.",
        "The new feature increased user retention by almost eight percent.",
        "Please update the Jira ticket once the bug is fixed.",
        "I appreciate your help on this, it saved us a lot of time.",
        "We should document the setup steps so new joiners can onboard faster.",
        "The marketing campaign goes live on Monday across all platforms.",
        "Can we push the release by a day to fix the login issue?",
        "I've added you to the shared folder on Google Drive.",
        // Code-mixed work
        "Bhai, yeh bug production mein aa gaya hai, jaldi fix karna padega.",
        "Kal ki meeting mein client ne naye requirements diye hain.",
        "Main deck ready kar raha hoon, shaam tak share kar dunga.",
        "Yeh feature next sprint mein le lete hain, abhi time kam hai.",
        "Please ek baar staging pe test kar lo, phir deploy karte hain.",
        "Mujhe lagta hai ki hume pricing page redesign karna chahiye.",
        "Server phir se down hai, DevOps team ko inform karo.",
        "Woh PR maine merge kar diya hai, ab tum rebase kar lo.",
        "Aaj ka standup cancel hai, sab apna update Slack pe daal do.",
        "Client ko demo dikhane se pehle ek baar end to end check kar lena.",
        "Is quarter ka target bahut aggressive hai, plan banana padega.",
        "Design wale ne naye mockups bheje hain, Figma mein dekh lo.",
        "Interview kaisa gaya? Candidate technically strong lag raha tha?",
        "Budget approve ho gaya hai, ab vendor se baat kar lete hain.",
        "Main laptop restart kar raha hoon, Zoom pe do minute mein join karta hoon.",
        "Yeh API response bahut slow hai, caching add karni padegi.",
        "Sabko email kar do ki office kal band rahega.",
        "Is document mein kuch typos hain, ek baar proofread kar lena.",
        "Customer ne refund maanga hai, finance team ko loop mein le lo.",
        "Hum log launch ke baad ek retro karenge.",
        "Data analysis ho gaya hai, insights kal share karunga.",
        "Mera Wi-Fi bahut slow chal raha hai, video band kar raha hoon.",
        "Woh contract legal team ne review kiya ya nahi?",
        "Naya intern kal se join kar raha hai, usko onboarding de dena.",
        "Product Hunt pe launch karne se pehle landing page update karna hai.",
        // Hindi-heavy
        "Main kal subah das baje office pahunch jaunga.",
        "Hum sab ko milkar is samasya ka samadhan nikalna hoga.",
        "Aapka bahut bahut dhanyavaad, aapne humari bahut madad ki.",
        "Kripya apna naam aur phone number yahan likh dijiye.",
        "Bachche school se ghar aa gaye hain aur khana kha rahe hain.",
        "Mujhe yeh kaam aaj hi khatam karna hai, kal chhutti hai.",
        "Pitaji ne kaha ki unki tabiyat ab pehle se behtar hai.",
        "Is saal baarish bahut zyada hui hai, kheton mein paani bhar gaya.",
        "Humari train shaam saat baje New Delhi station se chhutegi.",
        "Main aapse vinamra nivedan karta hoon ki aap samay par aayein.",
        "Yeh kitaab maine pichhle hafte padhi thi, bahut prerna dene wali hai.",
        "Hume apne swasthya ka dhyan rakhna chahiye aur roz vyayam karna chahiye.",
        "Dukaan wale ne kaha ki saaman kal tak aa jaayega.",
        "Meri maa ke haath ka khana duniya mein sabse achha hai.",
        "Kal se naya mahina shuru ho raha hai, kharche ka hisaab rakhna hai.",
        // Numbers, dates, money
        "My phone number is nine eight seven six five, four three two one zero.",
        "The meeting is on the twenty third of October at four PM.",
        "Total bill pandrah sau rupaye hua, aadha aadha kar lete hain.",
        "Please transfer twenty five thousand rupees to the vendor account.",
        "Flight ka time subah chhe bajkar pachaas minute hai.",
        "Our office is on the third floor, room number three zero four.",
        "Order number four five six seven eight hai, please check karo.",
        "Ticket ki keemat do hazaar paanch sau rupaye hai.",
        "The deadline is next Friday, the thirty first of October.",
        "Main dhai baje tak free ho jaunga, uske baad call karte hain.",
        // Questions and tone
        "Kya aapne aaj ka newspaper padha? Usmein ek interesting article tha.",
        "Why is the build failing on the main branch again?",
        "Kaun aa raha hai kal ki party mein? List bana lo.",
        "Is there any update from the bank regarding the loan?",
        "Tumhe kya lagta hai, yeh plan kaam karega ya nahi?",
        "How much time will it take to finish the migration?",
        "Kahan ho tum? Sab tumhara wait kar rahe hain.",
        "What do you think about moving the offsite to December?",
        "Kab tak ho jaayega yeh kaam? Client baar baar pooch raha hai.",
        "Should we order pizza for the team tonight?",
    ]

    /// Extra sentences built from the user's Dictionary vocabulary, so their own names and terms get recorded too.
    static func vocabularySentences(_ words: [String]) -> [String] {
        let templates = [
            "Please send this to %@ by tomorrow.",
            "Kal %@ ke saath meeting hai, details bhej do.",
            "I was talking about %@ in the last call.",
            "%@ ka update kya hai? Mujhe batana.",
        ]
        return words.prefix(24).enumerated().map { index, word in
            String(format: templates[index % templates.count], word)
        }
    }

    /// The full read-aloud list: fixed script followed by vocabulary sentences.
    static func all(vocabulary: [String]) -> [String] {
        sentences + vocabularySentences(vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
