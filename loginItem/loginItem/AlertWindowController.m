//
//  file: AlertWindowController.m
//  project: lulu (login item)
//  description: window controller for main firewall alert
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

#import <sys/socket.h>

#import "consts.h"
#import "logging.h"
#import "utilities.h"
#import "AppDelegate.h"
#import "DaemonComms.h"
#import "AlertWindowController.h"

@implementation AlertWindowController

@synthesize alert;
@synthesize signedIcon;
@synthesize processIcon;
@synthesize processName;
@synthesize ancestryButton;
@synthesize ancestryPopover;
@synthesize processHierarchy;
@synthesize virusTotalButton;
@synthesize virusTotalPopover;

//center window
// ->also, transparency
-(void)awakeFromNib
{
    //center
    [self.window center];
    
    //full size content view for translucency
    self.window.styleMask = self.window.styleMask | NSWindowStyleMaskFullSizeContentView;
    
    //title bar; translucency
    self.window.titlebarAppearsTransparent = YES;
    
    //move via background
    self.window.movableByWindowBackground = YES;
    
    return;
}

//delegate method
// populate/configure alert window
-(void)windowDidLoad
{
    //remote addr
    NSString* remoteAddress = nil;
    
    //timestamp formatter
    NSDateFormatter *timeFormat = nil;
    
    //init process hierarchy
    [self generateProcessAncestry:[self.alert[ALERT_PID] unsignedShortValue]];
    
    //disable ancestory button if no ancestors
    if(0 == self.processHierarchy.count)
    {
        //disable
        self.ancestryButton.enabled = NO;
    }
    
    //lulu allowed/blocked from talking to internet?
    // will fact, will determine state of virus total button
    [self setVTButtonState];

    //host name?
    if(nil != self.alert[ALERT_HOSTNAME])
    {
        //use host name
        remoteAddress = self.alert[ALERT_HOSTNAME];
    }
    
    //ip address
    else
    {
        //user ip addr
        remoteAddress = self.alert[ALERT_IPADDR];
    }
    
    /* TOP */
    
    //set process icon
    self.processIcon.image = getIconForProcess(self.alert[ALERT_PATH]);
    
    //process signing info
    [self processSigningInfo];
    
    //set name
    self.processName.stringValue = getProcessName(self.alert[ALERT_PATH]);
    
    //alert message
    self.alertMessage.stringValue = [NSString stringWithFormat:@"is trying to connect to %@", remoteAddress];
    
    /* BOTTOM */
    
    //process pid
    self.processID.stringValue = [self.alert[ALERT_PID] stringValue];
    
    //process path
    self.processPath.stringValue = self.alert[ALERT_PATH];
    
    //ip address
    self.ipAddress.stringValue = self.alert[ALERT_IPADDR];
    
    //port & proto
    self.portProto.stringValue = [NSString stringWithFormat:@"%@ (%@)", [self.alert[ALERT_PORT] stringValue], [self convertProtocol]];
    
    //alloc time formatter
    timeFormat = [[NSDateFormatter alloc] init];
    
    //set format
    timeFormat.dateFormat = @"HH:mm:ss";
    
    //add timestamp
    self.timeStamp.stringValue = [NSString stringWithFormat:@"time: %@", [timeFormat stringFromDate:[[NSDate alloc] init]]];
    
    //show touch bar
    [self initTouchBar];
    
bail:
    
    return;
}

//covert number protocol to name
-(NSString*)convertProtocol
{
    //protocol
    NSString* protocol = nil;
    
    //convert
    switch([self.alert[ALERT_PROTOCOL] intValue])
    {
        //tcp
        case SOCK_STREAM:
            
            //set
            protocol = @"TCP";
            
            break;
            
        //udp
        case SOCK_DGRAM:
            
            //set
            protocol = @"UDP";
            
            break;
            
        //??
        default:
            
            //set
            protocol = [NSString stringWithFormat:@"<unknown (%d)>", [self.alert[ALERT_PROTOCOL] intValue]];
    }
    
    return protocol;
}

//lulu allowed/blocked from talking to internet?
// will fact, will determine state of virus total button
-(void)setVTButtonState
{
    //flag
    __block BOOL shouldDisable = YES;
    
    //daemon comms object
    DaemonComms* daemonComms = nil;
    
    //init daemom comms
    daemonComms = [[DaemonComms alloc] init];
    
    //get rules from daemon via XPC
    [daemonComms getRules:NO reply:^(NSDictionary* daemonRules)
    {
         //look for an allow rule for lulu
         for(NSString* processPath in daemonRules.allKeys)
         {
             //is allow rule, match us?
             if( (YES == [processPath isEqualToString:NSProcessInfo.processInfo.arguments[0]]) &&
                 (RULE_STATE_ALLOW == [[daemonRules[processPath] objectForKey:RULE_ACTION] intValue]) )
             {
                 //dbg msg
                 logMsg(LOG_DEBUG, @"lulu/helper is allowed to access the network");
                 
                 //ok there is a rule for lulu, allowing it
                 // thus, virus total can be queried (i.e. it won't be blocked)
                 shouldDisable = NO;
                 
                 //done
                 break;
             }
         }
        
        //set button state on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //set state
            self.virusTotalButton.enabled = !shouldDisable;
            
        });
         
    }];
    
    return;
}

//set signing icon
// TODO: maybe make this popover w/ clickable/more info? (signing auths, etc)
-(void)processSigningInfo
{
    //signing info
    NSDictionary* signingInfo = nil;
    
    //extract
    signingInfo = self.alert[ALERT_SIGNINGINFO];
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"signing info: %@", signingInfo]);
    
    //none?
    // just set to unknown
    if(nil == signingInfo)
    {
        //set icon
        signedIcon.image = [NSImage imageNamed:@"unknown"];
        
        //bail
        goto bail;
    }
    
    switch([signingInfo[KEY_SIGNATURE_STATUS] intValue])
    {
        //happily signed
        case noErr:
            
            //item signed by apple
            if(YES == [signingInfo[KEY_SIGNING_IS_APPLE] boolValue])
            {
                //set icon
                signedIcon.image = [NSImage imageNamed:@"signedApple"];
                
                //set details
                //alertInfo[@"processSigning"] = @"Apple Code Signing Cert Auth";
            }
            //signed by dev id/ad hoc, etc
            else
            {
                //set icon
                signedIcon.image = [NSImage imageNamed:@"signed"];
                
                /*
                 
                //set signing auth
                if(0 != [signingInfo[KEY_SIGNING_AUTHORITIES] count])
                {
                    //add code-signing auth
                    alertInfo[@"processSigning"] = [signingInfo[KEY_SIGNING_AUTHORITIES] firstObject];
                }
                //no auths
                else
                {
                    //no auths
                    alertInfo[@"processSigning"] = @"no signing authorities (ad hoc?)";
                }
                */
            }
            
            break;
            
        //unsigned
        case errSecCSUnsigned:
            
            //set icon
            signedIcon.image = [NSImage imageNamed:@"unsigned"];
            
            //set details
            //alertInfo[@"processSigning"] = @"unsigned";
            
            break;
            
        default:
            
            //set icon
            signedIcon.image = [NSImage imageNamed:@"unknown"];
            
            //set details
            //alertInfo[@"processSigning"] = [NSString stringWithFormat:@"unknown (status/error: %ld)", (long)[signingInfo[KEY_SIGNATURE_STATUS] integerValue]];
    }
    
bail:
    
    return;
}

//automatically invoked when user clicks process vt button
// depending on state, show/populate the popup, or close it
-(IBAction)vtButtonHandler:(id)sender
{
    //view controller
    VirusTotalViewController* popoverVC = nil;
    
    //open popover
    if(NSOnState == self.virusTotalButton.state)
    {
        //grab
        popoverVC = (VirusTotalViewController*)self.virusTotalPopover.delegate;
        
        //set name
        popoverVC.itemName = self.processName.stringValue;
        
        //set path
        popoverVC.itemPath = self.processPath.stringValue;
        
        //show popover
        [self.virusTotalPopover showRelativeToRect:[self.virusTotalButton bounds] ofView:self.virusTotalButton preferredEdge:NSMaxYEdge];
    }
    
    //close popover
    else
    {
        //close
        [self.virusTotalPopover close];
    }
    
    return;
}

//invoked when user clicks process ancestry button
// depending on state, show/populate the popup, or close it
-(IBAction)ancestryButtonHandler:(id)sender
{
    //open popover
    if(NSOnState == self.ancestryButton.state)
    {
        //add the index value to each process in the hierarchy
        // used to populate outline/table
        for(NSUInteger i = 0; i<processHierarchy.count; i++)
        {
            //set index
            processHierarchy[i][@"index"] = [NSNumber numberWithInteger:i];
        }

        //set process hierarchy
        self.ancestryViewController.processHierarchy = processHierarchy;
        
        //dynamically (re)size popover
        [self setPopoverSize];
        
        //reload it
        [self.ancestryOutline reloadData];
        
        //auto-expand
        [self.ancestryOutline expandItem:nil expandChildren:YES];
        
        //show popover
        [self.ancestryPopover showRelativeToRect:[self.ancestryButton bounds] ofView:self.ancestryButton preferredEdge:NSMaxYEdge];
    }
    
    //close popover
    else
    {
        //close
        [self.ancestryPopover close];
    }
    
    return;
}

//build an array of processes ancestry
// start with process and go 'back' till initial ancestor
-(void)generateProcessAncestry:(pid_t)pid
{
    //process obj
    Process* process = nil;
    
    //init
    self.processHierarchy = [NSMutableArray array];
    
    //init (child) process
    process = [[Process alloc] init:pid];
    if(nil == process)
    {
        //bail
        goto bail;
    }
    
    //add process to hierarchy
    [self.processHierarchy insertObject:[@{@"pid":[NSNumber numberWithUnsignedInt:process.pid], @"name":process.binary.name} mutableCopy] atIndex:0];
    
    //now should have ancestors' pids
    // iterate over all ancestors, getting pid/name for each
    for(NSNumber* ancestorPID in process.ancestors)
    {
        //init process
        process = [[Process alloc] init:ancestorPID.unsignedIntValue];
        if(nil == process)
        {
            //bail
            goto bail;
        }
        
        //add process to hierarchy
        [self.processHierarchy insertObject:[@{@"pid":[NSNumber numberWithUnsignedInt:process.pid], @"name":process.binary.name} mutableCopy] atIndex:0];
    }
    
bail:
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"process ancestory: %@", self.processHierarchy]);
}

//set the popover window size
// ->make it roughly fit to content :)
-(void)setPopoverSize
{
    //popover's frame
    CGRect popoverFrame = {0};
    
    //required height
    CGFloat popoverHeight = 0.0f;
    
    //text of current row
    NSString* currentRow = nil;
    
    //width of current row
    CGFloat currentRowWidth = 0.0f;
    
    //length of max line
    CGFloat maxRowWidth = 0.0f;
    
    //extra rows
    NSUInteger extraRows = 0;
    
    //when hierarchy is less than 4
    // ->set (some) extra rows
    if(self.ancestryViewController.processHierarchy.count < 4)
    {
        //5 total
        extraRows = 4 - self.ancestryViewController.processHierarchy.count;
    }
    
    //calc total window height
    // ->number of rows + extra rows, * height
    popoverHeight = (self.ancestryViewController.processHierarchy.count + extraRows + 2) * [self.ancestryOutline rowHeight];
    
    //get window's frame
    popoverFrame = self.ancestryView.frame;
    
    //calculate max line width
    for(NSUInteger i=0; i<self.ancestryViewController.processHierarchy.count; i++)
    {
        //generate text of current row
        currentRow = [NSString stringWithFormat:@"%@ (pid: %@)", self.ancestryViewController.processHierarchy[i][@"name"], [self.ancestryViewController.processHierarchy lastObject][@"pid"]];
        
        //calculate width
        // ->first w/ indentation
        currentRowWidth = [self.ancestryOutline indentationPerLevel] * (i+1);
        
        //calculate width
        // ->then size of string in row
        currentRowWidth += [currentRow sizeWithAttributes: @{NSFontAttributeName: self.ancestryTextCell.font}].width;
        
        //save it greater than max
        if(maxRowWidth < currentRowWidth)
        {
            //save
            maxRowWidth = currentRowWidth;
        }
    }
    
    //add some padding
    // ->scroll bar, etc
    maxRowWidth += 50;
    
    //set height
    popoverFrame.size.height = popoverHeight;
    
    //set width
    popoverFrame.size.width = maxRowWidth;
    
    //set new frame
    self.ancestryView.frame = popoverFrame;
    
    return;
}


//logic to close/remove popups from view
// ->needed, otherwise random memory issues occur :/
-(void)deInitPopup
{
    //virus total popup
    if(NSOnState == self.virusTotalButton.state)
    {
        //close
        [self.virusTotalPopover close];
    
        //set button state to off
        self.virusTotalButton.state = NSOffState;
    }
    
    //process ancestry popup
    if(NSOnState == self.ancestryButton.state)
    {
        //close
        [self.ancestryPopover close];
        
        //set button state to off
        self.ancestryButton.state = NSOffState;
    }
    
    return;
}

//button handler
// close popups and stop modal with resposne
-(IBAction)handleUserResponse:(id)sender
{
    //ensure popups are closed
    [self deInitPopup];
    
    //close window
    [self.window close];
    
    //stop modal
    [[NSApplication sharedApplication] stopModalWithCode:((NSButton*)sender).tag];
    
    return;
}

//init/show touch bar
-(void)initTouchBar
{
    //touch bar items
    NSArray *touchBarItems = nil;
    
    //touch bar API is only 10.12.2+
    if(@available(macOS 10.12.2, *))
    {
        //alloc/init
        self.touchBar = [[NSTouchBar alloc] init];
        if(nil == self.touchBar)
        {
            //no touch bar?
            goto bail;
        }
        
        //set delegate
        self.touchBar.delegate = self;
        
        //set id
        self.touchBar.customizationIdentifier = @"com.objective-see.lulu";
        
        //init items
        touchBarItems = @[@".icon", @".label", @".block", @".allow"];
        
        //set items
        self.touchBar.defaultItemIdentifiers = touchBarItems;
        
        //set customization items
        self.touchBar.customizationAllowedItemIdentifiers = touchBarItems;
        
        //activate so touchbar shows up
        [NSApp activateIgnoringOtherApps:YES];
    }
    
bail:
    
    return;
}

//delegate method
// init item for touch bar
-(NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    //icon view
    NSImageView *iconView = nil;
    
    //icon
    NSImage* icon = nil;
    
    //item
    NSCustomTouchBarItem *touchBarItem = nil;
    
    //init item
    touchBarItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    
    //icon
    if(YES == [identifier isEqualToString: @".icon" ])
    {
        //init icon view
        iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 30.0, 30.0)];
        
        //enable layer
        [iconView setWantsLayer:YES];
        
        //set color
        [iconView.layer setBackgroundColor:[[NSColor whiteColor] CGColor]];
        
        //mask
        iconView.layer.masksToBounds = YES;
        
        //round corners
        iconView.layer.cornerRadius = 3.0;
        
        //load icon image
        icon = [NSImage imageNamed:@"luluIcon"];
        
        //set size
        icon.size = CGSizeMake(32, 32);
        
        //add image
        iconView.image = icon;
        
        //set view
        touchBarItem.view = iconView;
    }
    
    //label
    else if(YES == [identifier isEqualToString:@".label"])
    {
        //item label
        touchBarItem.view = [NSTextField labelWithString:[NSString stringWithFormat:@"%@ %@", self.processName.stringValue,self.alertMessage.stringValue]];
    }
    
    //block button
    else if(YES == [identifier isEqualToString:@".block"])
    {
        //init button
        touchBarItem.view = [NSButton buttonWithTitle: @"Block" target:self action: @selector(handleUserResponse:)];
        
        //set tag
        // 0: block
        ((NSButton*)touchBarItem.view).tag = 0;
    }
    
    //allow button
    else if(YES == [identifier isEqualToString:@".allow"])
    {
        //init button
        touchBarItem.view = [NSButton buttonWithTitle: @"Allow" target:self action: @selector(handleUserResponse:)];
        
        //set tag
        // 1: allow
        ((NSButton*)touchBarItem.view).tag = 1;
    }
    
    return touchBarItem;
}

@end
